import re
import subprocess
import sys
from pathlib import Path

import pytest
from playwright.sync_api import Page, expect

from scripts.blueprint_harness_paths import canonical_test_blueprint_output_dir
from scripts.blueprint_harness_project_commands import rebuild_and_log_embedded_asset_owners
from scripts.blueprint_harness_utils import lean_low_priority_command
from support import PACKAGE_ROOT, blueprint_render_api_script, find_free_port, wait_for_server


@pytest.fixture(scope="session")
def preview_runtime_showcase_output_dir() -> Path:
    output_dir = canonical_test_blueprint_output_dir("preview_runtime_showcase", Path(__file__))
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    project_dir = PACKAGE_ROOT / "tests" / "test_blueprints" / "preview_runtime_showcase"
    rebuild_and_log_embedded_asset_owners(PACKAGE_ROOT)
    subprocess.run(
        lean_low_priority_command(PACKAGE_ROOT, "lake", "build", "PreviewRuntimeShowcase"),
        cwd=project_dir,
        check=True,
    )
    subprocess.run(
        lean_low_priority_command(
            PACKAGE_ROOT,
            "lake",
            "lean",
            "PreviewRuntimeShowcaseMain.lean",
            "--",
            "--run",
            "PreviewRuntimeShowcaseMain.lean",
            "--output",
            str(output_dir),
            "--with-html-single",
            "--without-html-multi",
        ),
        cwd=project_dir,
        check=True,
    )
    return output_dir


@pytest.fixture(scope="session")
def preview_runtime_showcase_root_server(preview_runtime_showcase_output_dir: Path):
    port = find_free_port()
    proc = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"],
        cwd=preview_runtime_showcase_output_dir,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    server_url = f"http://127.0.0.1:{port}"
    wait_for_server(server_url, proc)
    yield server_url
    proc.terminate()
    proc.wait()


def wait_for_graph(page: Page):
    page.wait_for_function(
        """() => {
            const canvas = document.querySelector(".bp_graph_canvas");
            const svg = canvas ? canvas.querySelector("svg") : null;
            return !!canvas && !!svg;
        }"""
    )


def goto_graph_page(page: Page, url: str):
    page.goto(url, wait_until="domcontentloaded", timeout=60000)


def wait_for_rendered_variant(page: Page, variant: str):
    page.wait_for_function(
        """(expectedVariant) => {
            const block = document.querySelector(".bp_graph_fullwidth");
            const canvas = document.querySelector(".bp_graph_canvas");
            const select = document.querySelector(".bp_graph_view_select");
            const svg = canvas ? canvas.querySelector("svg") : null;
            const state = block ? block.__bpGraphState : null;
            return (
                !!select &&
                !!svg &&
                !!state &&
                select.value === expectedVariant &&
                state.renderedVariantKey === expectedVariant &&
                state.renderFinalizedToken === state.renderToken
            );
        }""",
        arg=variant,
    )


def graph_transform(page: Page):
    return page.evaluate(
        """() => {
            const canvas = document.querySelector(".bp_graph_canvas");
            const svg = canvas ? canvas.querySelector("svg") : null;
            const graph = svg ? (svg.querySelector("g.graph") || svg.querySelector("g")) : null;
            return graph ? graph.getAttribute("transform") : null;
        }"""
    )


def assert_graph_has_zoom_handlers(page: Page):
    assert page.evaluate(
        """() => {
            const svg = document.querySelector(".bp_graph_canvas svg");
            if (!svg || !Array.isArray(svg.__on) || !svg.__zoom) return false;
            return svg.__on.some((entry) => entry.type === "mousedown" && entry.name === "zoom");
        }"""
    )


def assert_graph_can_be_dragged(page: Page):
    before = graph_transform(page)
    assert before is not None
    canvas_box = page.locator(".bp_graph_canvas").first.bounding_box()
    assert canvas_box is not None
    center_x = canvas_box["x"] + canvas_box["width"] / 2
    center_y = canvas_box["y"] + canvas_box["height"] / 2
    page.mouse.move(center_x, center_y)
    page.mouse.down()
    page.mouse.move(center_x + 90, center_y + 36, steps=6)
    page.mouse.up()
    page.wait_for_function(
        """(previousTransform) => {
            const canvas = document.querySelector(".bp_graph_canvas");
            const svg = canvas ? canvas.querySelector("svg") : null;
            const graph = svg ? (svg.querySelector("g.graph") || svg.querySelector("g")) : null;
            return !!graph && graph.getAttribute("transform") !== previousTransform;
        }""",
        arg=before,
    )


def graph_visibility_metrics(page: Page):
    return page.evaluate(
        """() => {
            const canvas = document.querySelector(".bp_graph_canvas");
            const svg = canvas ? canvas.querySelector("svg") : null;
            const graph = svg ? (svg.querySelector("g.graph") || svg.querySelector("g")) : null;
            if (!canvas || !svg || !graph) return null;
            const canvasRect = canvas.getBoundingClientRect();
            const graphRect = graph.getBoundingClientRect();
            return {
                canvasTop: canvasRect.top,
                canvasHeight: canvasRect.height,
                graphTop: graphRect.top,
                graphBottom: graphRect.bottom,
            };
        }"""
    )


def graph_dimensions(page: Page):
    return page.evaluate(
        """() => {
            const canvas = document.querySelector(".bp_graph_canvas");
            const svg = canvas ? canvas.querySelector("svg") : null;
            const graph = svg ? (svg.querySelector("g.graph") || svg.querySelector("g")) : null;
            if (!canvas || !svg || !graph) return null;
            const graphRect = graph.getBoundingClientRect();
            return {
                width: graphRect.width,
                height: graphRect.height,
                activeDirection: canvas.getAttribute("data-bp-active-direction") || "",
                activePack: canvas.getAttribute("data-bp-active-pack") || "",
            };
        }"""
    )


def assert_graph_is_well_placed(page: Page):
    metrics = graph_visibility_metrics(page)
    assert metrics is not None
    assert metrics["graphTop"] < metrics["canvasTop"] + 0.35 * metrics["canvasHeight"]
    assert metrics["graphBottom"] > metrics["canvasTop"] + 0.5 * metrics["canvasHeight"]


def first_preview_node(page: Page):
    node = page.locator(".bp_graph_canvas svg g.node[tabindex='0']").first
    node.wait_for()
    return node


def preview_node_by_label(page: Page, label: str):
    node = page.locator(".bp_graph_canvas svg g.node[tabindex='0']").filter(has_text=label).first
    node.wait_for()
    return node


class TestGraphLayoutRuntime:
    def test_public_graph_api_exposes_rendered_page_and_manifest_data(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")

        graph_data = page.evaluate(
            blueprint_render_api_script(
                """
                const block = document.querySelector(".bp_graph_fullwidth");
                const graphModule = await import(api.graphApiModuleUrl());
                const pageGraph = graphModule.getGraphData(block);
                const manifestGraphs = await graphModule.loadGraphs();
                const manifestGraph = manifestGraphs.find((graph) => graph.key === pageGraph.key) || null;
                const variants = graphModule.getGraphVariants(block);
                const sample = pageGraph.nodes.find((node) => node.label === "used_target") || null;
                const manifestSample = manifestGraph
                    ? manifestGraph.nodes.find((node) => node.label === "used_target") || null
                    : null;
                const topologySnapshot = (graph) => JSON.stringify({
                    nodes: graph.nodes.map((node) => ({
                        label: node.label,
                        parent: node.parent,
                        statementUses: node.statementUses,
                        proofUses: node.proofUses
                    })),
                    edges: graph.edges,
                    groups: graph.groups,
                    variants: graph.variants.map((variant) => ({
                        key: variant.key,
                        label: variant.label,
                        dot: variant.dot,
                        options: variant.options,
                        selectOnNodeId: variant.selectOnNodeId,
                        hoverOnNodeId: variant.hoverOnNodeId
                    }))
                });
                return {
                    hasLegacyGlobal: typeof window.bpGraphApi !== "undefined",
                    previewHasGraphData: typeof api.getGraphData === "function",
                    previewHasLoadGraphs: typeof api.loadGraphs === "function",
                    previewHasGraphApiModuleUrl: typeof api.graphApiModuleUrl === "function",
                    pageKey: pageGraph.key,
                    manifestGraphs: manifestGraphs.length,
                    manifestKey: manifestGraph ? manifestGraph.key : "",
                    pageNodes: pageGraph.nodes.length,
                    pageEdges: pageGraph.edges.length,
                    pageGroups: pageGraph.groups.length,
                    manifestNodes: manifestGraph ? manifestGraph.nodes.length : 0,
                    manifestEdges: manifestGraph ? manifestGraph.edges.length : 0,
                    manifestGroups: manifestGraph ? manifestGraph.groups.length : 0,
                    pageSchemaVersion: pageGraph.schemaVersion,
                    manifestSchemaVersion: manifestGraph ? manifestGraph.schemaVersion : 0,
                    topologyMatches: manifestGraph
                        ? topologySnapshot(pageGraph) === topologySnapshot(manifestGraph)
                        : false,
                    variantKeys: variants.map((variant) => variant.key),
                    sampleTitle: sample ? sample.title : "",
                    sampleHref: sample ? sample.href : "",
                    manifestSampleTitle: manifestSample ? manifestSample.title : "",
                    manifestSampleHref: manifestSample ? manifestSample.href : ""
                };
                """
            )
        )

        assert graph_data["hasLegacyGlobal"] is False
        assert graph_data["previewHasGraphData"] is False
        assert graph_data["previewHasLoadGraphs"] is False
        assert graph_data["previewHasGraphApiModuleUrl"] is True
        assert graph_data["pageKey"].startswith("graph:#<")
        assert graph_data["manifestGraphs"] == 1
        assert graph_data["manifestKey"] == graph_data["pageKey"]
        assert graph_data["pageNodes"] >= 55
        assert graph_data["pageEdges"] >= 13
        assert graph_data["pageGroups"] >= 3
        assert graph_data["manifestNodes"] == graph_data["pageNodes"]
        assert graph_data["manifestEdges"] == graph_data["pageEdges"]
        assert graph_data["manifestGroups"] == graph_data["pageGroups"]
        assert graph_data["pageSchemaVersion"] == 3
        assert graph_data["manifestSchemaVersion"] == 3
        assert graph_data["topologyMatches"]
        assert {"full", "group"}.issubset(set(graph_data["variantKeys"]))
        assert graph_data["sampleTitle"].startswith("Definition")
        assert graph_data["sampleHref"] == "Preview-Relationships/#--informal-preview-used_target--statement"
        assert graph_data["manifestSampleTitle"] == graph_data["sampleTitle"]
        assert graph_data["manifestSampleHref"] == graph_data["sampleHref"]

    def test_public_graph_api_rejects_obsolete_or_malformed_records(
        self, server: str, page: Page
    ):
        goto_graph_page(page, f"{server}/Dependency-Graph/")

        keys = page.evaluate(
            blueprint_render_api_script(
                """
                const graphModule = await import(api.graphApiModuleUrl());
                const fullVariant = {
                    key: "full",
                    label: "Full Graph",
                    dot: "strict digraph {}",
                    options: { direction: "TB", pack: false },
                    selectOnNodeId: [],
                    hoverOnNodeId: [],
                    previewKeyByNodeId: []
                };
                const completeRecord = (schemaVersion, key, variants) => ({
                    schemaVersion,
                    key,
                    nodes: [],
                    edges: [],
                    groups: [],
                    variants
                });
                const graphs = await graphModule.loadManifestGraphs(
                    "https://example.invalid/blueprint-manifest.json",
                    {
                        fetchJson: () => ({
                            graphs: [
                                completeRecord(3, "graph:current", [fullVariant]),
                                completeRecord(2, "graph:obsolete-schema", [fullVariant]),
                                completeRecord(3, "graph:no-variants", []),
                                completeRecord(3, "graph:blank-dot", [
                                    { ...fullVariant, dot: " " }
                                ]),
                                completeRecord(3, "graph:invalid-options", [
                                    { ...fullVariant, options: { direction: "sideways", pack: false } }
                                ]),
                                completeRecord(3, "graph:invalid-pair", [
                                    { ...fullVariant, previewKeyByNodeId: [["node-only"]] }
                                ]),
                                completeRecord(3, "graph:duplicate-variant", [
                                    fullVariant,
                                    { ...fullVariant, label: "Duplicate Full Graph" }
                                ]),
                                completeRecord(3, "graph:missing-full", [
                                    { ...fullVariant, key: "group", label: "Group View" }
                                ]),
                                completeRecord(3, "graph:unknown-variant-target", [
                                    { ...fullVariant, selectOnNodeId: [["node-id", "missing"]] }
                                ]),
                                completeRecord(3, "graph:duplicate-node-mapping", [
                                    {
                                        ...fullVariant,
                                        previewKeyByNodeId: [
                                            ["node-id", "preview:first"],
                                            ["node-id", "preview:second"]
                                        ]
                                    }
                                ]),
                                {
                                    schemaVersion: 3,
                                    key: "graph:incomplete-record",
                                    nodes: [],
                                    edges: [],
                                    groups: []
                                }
                            ]
                        })
                    }
                );
                return graphs.map((graph) => graph.key);
                """
            )
        )

        assert keys == ["graph:current"]

    def test_public_graph_api_can_render_copied_graph_block(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        result = page.evaluate(
            blueprint_render_api_script(
                """
                const source = document.querySelector(".bp_graph_fullwidth");
                if (!source) return { ok: false, reason: "missing source graph" };
                const clone = source.cloneNode(true);
                clone.querySelectorAll("svg").forEach((svg) => svg.remove());
                const host = document.createElement("section");
                host.id = "copied-graph-host";
                host.style.height = "520px";
                host.style.marginTop = "24px";
                host.appendChild(clone);
                document.body.appendChild(host);

                const graphModule = await import(api.graphApiModuleUrl());
                const controller = await graphModule.renderGraphBlock(clone, {
                    previewUtils: api,
                    layout: "fill"
                });
                await new Promise((resolve, reject) => {
                    const startedAt = performance.now();
                    const check = () => {
                        const canvas = clone.querySelector(".bp_graph_canvas");
                        const svg = canvas ? canvas.querySelector("svg") : null;
                        const state = clone.__bpGraphState || null;
                        if (
                            canvas &&
                            svg &&
                            state &&
                            state.renderFinalizedToken === state.renderToken
                        ) {
                            resolve();
                            return;
                        }
                        if (performance.now() - startedAt > 5000) {
                            reject(new Error("copied graph block did not render"));
                            return;
                        }
                        setTimeout(check, 50);
                    };
                    check();
                });
                const canvas = clone.querySelector(".bp_graph_canvas");
                const svg = canvas ? canvas.querySelector("svg") : null;
                return {
                    ok: true,
                    moduleRenderGraphBlock: typeof graphModule.renderGraphBlock === "function",
                    moduleRenderGraphs: typeof graphModule.renderGraphs === "function",
                    runtimeRenderGraphBlock: typeof api.renderGraphBlock === "function",
                    runtimeRenderGraphs: typeof api.renderGraphs === "function",
                    controller: !!controller && controller === clone.__bpGraphController,
                    layout: clone.getAttribute("data-bp-graph-layout") || "",
                    canvasLayout: canvas ? (canvas.getAttribute("data-bp-graph-layout") || "") : "",
                    canvasHeight: canvas ? canvas.getBoundingClientRect().height : 0,
                    hasSvg: !!svg,
                    activeVariant: clone.__bpGraphState ? clone.__bpGraphState.renderedVariantKey : ""
                };
                """
            )
        )

        assert result["ok"], result
        assert result["moduleRenderGraphBlock"]
        assert result["moduleRenderGraphs"]
        assert result["runtimeRenderGraphBlock"]
        assert result["runtimeRenderGraphs"]
        assert result["controller"]
        assert result["layout"] == "fill"
        assert result["canvasLayout"] == "fill"
        assert result["canvasHeight"] > 300
        assert result["hasSvg"]
        assert result["activeVariant"] == "full"

    def test_public_graph_api_can_render_manifest_graph_data(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        result = page.evaluate(
            blueprint_render_api_script(
                """
                const graphModule = await import(api.graphApiModuleUrl());
                const graphs = await graphModule.loadGraphs();
                const graph = graphs[0] || null;
                if (!graph) return { ok: false, reason: "missing manifest graph" };
                const manifestVariantKeys = Array.isArray(graph.variants)
                    ? graph.variants.map((variant) => variant.key)
                    : [];

                const detached = await graphModule.createGraphBlock(graph, {
                    layout: "fill",
                    graphOptions: { direction: "LR", pack: true }
                });
                const detachedData = graphModule.getGraphData(detached);
                const detachedVariants = graphModule.getGraphVariants(detached);

                const host = document.createElement("section");
                host.id = "manifest-graph-host";
                host.style.height = "520px";
                host.style.marginTop = "24px";
                document.body.appendChild(host);

                const controller = await graphModule.renderGraphData(host, graph, {
                    previewUtils: api,
                    layout: "fill",
                    graphOptions: { direction: "LR", pack: true }
                });
                const block = host.querySelector(".bp_graph_fullwidth");
                await new Promise((resolve, reject) => {
                    const startedAt = performance.now();
                    const check = () => {
                        const canvas = block ? block.querySelector(".bp_graph_canvas") : null;
                        const svg = canvas ? canvas.querySelector("svg") : null;
                        const state = block ? block.__bpGraphState || null : null;
                        if (
                            canvas &&
                            svg &&
                            state &&
                            state.renderFinalizedToken === state.renderToken
                        ) {
                            resolve();
                            return;
                        }
                        if (performance.now() - startedAt > 5000) {
                            reject(new Error("manifest graph data did not render"));
                            return;
                        }
                        setTimeout(check, 50);
                    };
                    check();
                });
                const canvas = block ? block.querySelector(".bp_graph_canvas") : null;
                const svg = canvas ? canvas.querySelector("svg") : null;
                const state = block ? block.__bpGraphState || null : null;
                const select = block ? block.querySelector(".bp_graph_view_select") : null;
                const directionSelect = block ? block.querySelector(".bp_graph_direction_select") : null;
                const packInput = block ? block.querySelector(".bp_graph_pack_input") : null;
                return {
                    ok: true,
                    moduleCreateGraphBlock: typeof graphModule.createGraphBlock === "function",
                    moduleRenderGraphData: typeof graphModule.renderGraphData === "function",
                    runtimeCreateGraphBlock: typeof api.createGraphBlock === "function",
                    runtimeRenderGraphData: typeof api.renderGraphData === "function",
                    manifestVariantKeys,
                    detachedBlock: !!detached && detached.matches(".bp_graph_fullwidth"),
                    detachedKey: detachedData ? detachedData.key : "",
                    detachedVariantKeys: detachedVariants.map((variant) => variant.key),
                    hostChildCount: host.children.length,
                    controller: !!controller && !!block && controller === block.__bpGraphController,
                    layout: block ? (block.getAttribute("data-bp-graph-layout") || "") : "",
                    canvasLayout: canvas ? (canvas.getAttribute("data-bp-graph-layout") || "") : "",
                    hasSvg: !!svg,
                    activeVariant: state ? state.renderedVariantKey : "",
                    viewCount: select ? select.options.length : 0,
                    direction: directionSelect ? directionSelect.value : "",
                    pack: packInput ? packInput.checked : false
                };
                """
            )
        )

        assert result["ok"], result
        assert result["moduleCreateGraphBlock"]
        assert result["moduleRenderGraphData"]
        assert result["runtimeCreateGraphBlock"]
        assert result["runtimeRenderGraphData"]
        assert {"full", "group"}.issubset(set(result["manifestVariantKeys"]))
        assert result["detachedBlock"]
        assert result["detachedKey"].startswith("graph:#<")
        assert {"full", "group"}.issubset(set(result["detachedVariantKeys"]))
        assert result["hostChildCount"] == 1
        assert result["controller"]
        assert result["layout"] == "fill"
        assert result["canvasLayout"] == "fill"
        assert result["hasSvg"]
        assert result["activeVariant"] == "full"
        assert result["viewCount"] >= 2
        assert result["direction"] == "LR"
        assert result["pack"] is True

    def test_single_page_graph_canvas_does_not_collapse(
        self,
        preview_runtime_showcase_root_server: str,
        page: Page,
    ):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{preview_runtime_showcase_root_server}/html-single/")
        wait_for_graph(page)

        metrics = page.evaluate(
            """() => {
                const block = document.querySelector(".bp_graph_fullwidth");
                const canvas = document.querySelector(".bp_graph_canvas");
                const svg = canvas ? canvas.querySelector("svg") : null;
                const state = block ? block.__bpGraphState : null;
                if (!block || !canvas || !svg || !state) return null;
                const canvasRect = canvas.getBoundingClientRect();
                const svgRect = svg.getBoundingClientRect();
                return {
                    canvasHeight: canvasRect.height,
                    svgHeight: svgRect.height,
                    rendered: state.renderFinalizedToken === state.renderToken,
                    layout: canvas.getAttribute("data-bp-graph-layout") || "",
                    path: window.location.pathname,
                };
            }"""
        )

        assert metrics is not None
        assert metrics["path"].endswith("/html-single/")
        assert metrics["rendered"]
        assert metrics["layout"] == ""
        assert metrics["canvasHeight"] > 240
        assert metrics["svgHeight"] > 200

    def test_single_page_custom_graph_clients_use_generated_api_urls(
        self,
        preview_runtime_showcase_root_server: str,
        page: Page,
    ):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{preview_runtime_showcase_root_server}/html-single/")

        client = page.locator("#custom-render-client-example").first
        expect(client).to_have_attribute("data-bp-custom-client-status", "ready", timeout=15000)

        preview_module_card = page.locator("[data-bp-preview-module-example]").first
        expect(preview_module_card).to_have_attribute("data-bp-preview-module-ok", "true")
        expect(preview_module_card).to_have_attribute("data-bp-preview-module-render-api", "true")

        graph_card = page.locator("[data-bp-custom-client-graph]").first
        expect(graph_card).to_have_attribute("data-bp-graph-ok", "true")
        expect(graph_card).to_have_attribute("data-bp-graph-count", "1")
        expect(graph_card).to_have_attribute("data-bp-graph-module-ok", "true")
        expect(graph_card).to_have_attribute("data-bp-graph-module-count", "1")
        expect(graph_card.locator("[data-bp-custom-client-graph-summary]").first).to_contain_text(
            "Nodes 58"
        )

    def test_graph_legend_is_collapsed_by_default_and_tracks_variant_switch(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        button = page.locator(".bp_graph_legend_button").first
        panel = page.locator(".bp_graph_legend_popover").first
        selector = page.locator(".bp_graph_view_select").first

        assert button.get_attribute("aria-expanded") == "false"
        assert panel.evaluate("el => el.hidden") is True

        button.click()
        page.wait_for_function(
            """() => {
                const button = document.querySelector(".bp_graph_legend_button");
                const panel = document.querySelector(".bp_graph_legend_popover");
                const fullLegend = document.querySelector('.bp_graph_legend[data-bp-legend-kind="full"]');
                return (
                    !!button &&
                    !!panel &&
                    button.getAttribute("aria-expanded") === "true" &&
                    !panel.hidden &&
                    !!fullLegend &&
                    !fullLegend.hidden
                );
            }"""
        )

        selector.select_option("group")
        page.wait_for_function(
            """() => {
                const select = document.querySelector(".bp_graph_view_select");
                const fullLegend = document.querySelector('.bp_graph_legend[data-bp-legend-kind="full"]');
                const groupLegend = document.querySelector('.bp_graph_legend[data-bp-legend-kind="group"]');
                return (
                    !!select &&
                    !!fullLegend &&
                    !!groupLegend &&
                    select.value === "group" &&
                    fullLegend.hidden &&
                    !groupLegend.hidden
                );
            }"""
        )

    def test_graph_options_popover_switches_direction(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        options_button = page.locator(".bp_graph_options_button").first
        options_panel = page.locator(".bp_graph_options_popover").first
        direction_selector = page.locator(".bp_graph_direction_select").first
        pack_input = page.locator(".bp_graph_pack_input").first

        initial = graph_dimensions(page)
        assert initial is not None
        assert initial["activeDirection"] == "TB"
        assert initial["activePack"] == "true"

        options_button.click()
        page.wait_for_function(
            """() => {
                const button = document.querySelector(".bp_graph_options_button");
                const panel = document.querySelector(".bp_graph_options_popover");
                const select = document.querySelector(".bp_graph_direction_select");
                const pack = document.querySelector(".bp_graph_pack_input");
                return (
                    !!button &&
                    !!panel &&
                    !!select &&
                    !!pack &&
                    button.getAttribute("aria-expanded") === "true" &&
                    !panel.hidden &&
                    select.value === "TB" &&
                    pack.checked
                );
            }"""
        )

        direction_selector.select_option("LR")
        page.wait_for_function(
            """() => {
                const canvas = document.querySelector(".bp_graph_canvas");
                const select = document.querySelector(".bp_graph_direction_select");
                const panel = document.querySelector(".bp_graph_options_popover");
                return (
                    !!canvas &&
                    !!select &&
                    !!panel &&
                    select.value === "LR" &&
                    canvas.getAttribute("data-bp-active-direction") === "LR" &&
                    panel.hidden
                );
            }"""
        )

        options_button.click()
        page.wait_for_function(
            """() => {
                const panel = document.querySelector(".bp_graph_options_popover");
                const pack = document.querySelector(".bp_graph_pack_input");
                return !!panel && !!pack && !panel.hidden && pack.checked;
            }"""
        )
        pack_input.uncheck()
        page.wait_for_function(
            """() => {
                const block = document.querySelector(".bp_graph_fullwidth");
                const canvas = document.querySelector(".bp_graph_canvas");
                const pack = document.querySelector(".bp_graph_pack_input");
                const state = block ? block.__bpGraphState : null;
                return (
                    !!canvas &&
                    !!pack &&
                    !!state &&
                    !pack.checked &&
                    canvas.getAttribute("data-bp-active-pack") === "false" &&
                    state.renderFinalizedToken === state.renderToken
                );
            }"""
        )
        pack_input.check()
        page.wait_for_function(
            """() => {
                const block = document.querySelector(".bp_graph_fullwidth");
                const canvas = document.querySelector(".bp_graph_canvas");
                const pack = document.querySelector(".bp_graph_pack_input");
                const state = block ? block.__bpGraphState : null;
                return (
                    !!canvas &&
                    !!pack &&
                    !!state &&
                    pack.checked &&
                    canvas.getAttribute("data-bp-active-pack") === "true" &&
                    state.renderFinalizedToken === state.renderToken
                );
            }"""
        )

        switched = graph_dimensions(page)
        assert switched is not None
        assert switched["activeDirection"] == "LR"
        assert switched["activePack"] == "true"
        assert switched["width"] > switched["height"]
        assert_graph_is_well_placed(page)

    def test_graph_options_popover_uses_readable_mobile_width(self, server: str, page: Page):
        page.set_viewport_size({"width": 390, "height": 844})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        page.locator(".bp_graph_options_button").first.click()
        metrics = page.evaluate(
            """() => {
                const block = document.querySelector(".bp_graph_fullwidth");
                const panel = document.querySelector(".bp_graph_options_popover");
                if (!block || !panel) return null;
                const blockRect = block.getBoundingClientRect();
                const panelRect = panel.getBoundingClientRect();
                return {
                    hidden: panel.hidden,
                    blockWidth: blockRect.width,
                    panelWidth: panelRect.width,
                    leftDelta: Math.abs(panelRect.left - blockRect.left),
                    rightDelta: Math.abs(panelRect.right - blockRect.right)
                };
            }"""
        )

        assert metrics is not None
        assert metrics["hidden"] is False
        assert metrics["panelWidth"] >= min(280, metrics["blockWidth"] * 0.75)
        assert metrics["leftDelta"] <= 1

    def test_graph_preview_defaults_to_pinned(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        panel = page.locator(".bp_graph_preview").first
        node = preview_node_by_label(page, "used_target")

        assert panel.get_attribute("data-bp-preview-mode") == "pinned"
        assert panel.get_attribute("data-bp-preview-placement") == "docked"

        node.hover()
        page.wait_for_timeout(250)
        assert panel.evaluate("el => el.hidden") is True

        node.click()
        page.wait_for_function(
            """() => {
                const panel = document.querySelector(".bp_graph_preview");
                return !!panel && !panel.hidden && panel.getAttribute("data-bp-preview-mode") === "pinned";
            }"""
        )
        title_link = panel.locator(".bp_graph_preview_title a").first
        expect(title_link).to_contain_text("Definition")
        expect(title_link).to_have_attribute(
            "href", re.compile(r"Preview-Relationships/#--informal-preview-used_target--statement$")
        )
        expect(title_link).to_have_attribute("title", "used_target")
        options_button = page.locator(".bp_graph_options_button").first
        options_button.click()
        page.wait_for_function(
            """() => {
                const button = document.querySelector(".bp_graph_options_button");
                const panel = document.querySelector(".bp_graph_options_popover");
                const preview = document.querySelector(".bp_graph_preview");
                return (
                    !!button &&
                    !!panel &&
                    !!preview &&
                    !preview.hidden &&
                    !panel.hidden &&
                    button.getAttribute("aria-expanded") === "true"
                );
            }"""
        )
        page.locator(".bp_graph_options_popover_close").first.click()
        page.wait_for_function(
            """() => {
                const button = document.querySelector(".bp_graph_options_button");
                const panel = document.querySelector(".bp_graph_options_popover");
                return !!button && !!panel && panel.hidden && button.getAttribute("aria-expanded") === "false";
            }"""
        )
        page.mouse.move(20, 20)
        page.wait_for_timeout(250)
        assert panel.evaluate("el => el.hidden") is False

        title_link.click()
        page.wait_for_url(re.compile(r".*/Preview-Relationships/#--informal-preview-used_target--statement$"))
        page.go_back()
        wait_for_graph(page)
        panel = page.locator(".bp_graph_preview").first
        node = preview_node_by_label(page, "used_target")
        node.click()
        page.wait_for_function(
            """() => {
                const panel = document.querySelector(".bp_graph_preview");
                return !!panel && !panel.hidden && panel.getAttribute("data-bp-preview-mode") === "pinned";
            }"""
        )

        page.locator(".bp_graph_preview_close").first.click()
        page.wait_for_function(
            """() => {
                const panel = document.querySelector(".bp_graph_preview");
                return !!panel && panel.hidden;
            }"""
        )

    def test_render_api_surface_normalizes_graph_preview_behavior(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        assert page.evaluate(
            blueprint_render_api_script(
                """
                if (
                    typeof api.normalizePreviewMode !== "undefined" ||
                    typeof api.normalizePreviewPlacement !== "undefined" ||
                    typeof api.readPanelBehavior !== "undefined"
                ) {
                    return false;
                }
                const panel = document.createElement("aside");
                panel.innerHTML = [
                    '<div class="bp_test_title"></div>',
                    '<button class="bp_test_close" type="button">Close</button>',
                    '<div class="bp_test_body"></div>'
                ].join("");
                document.body.appendChild(panel);
                const surface = api.createPreviewSurface({
                    panel: panel,
                    titleSelector: ".bp_test_title",
                    bodySelector: ".bp_test_body",
                    closeSelector: ".bp_test_close",
                    defaults: { mode: "pinned", placement: "anchored" }
                });
                if (!surface) return false;
                const defaultBehavior = surface.behavior;
                const panelBehavior = surface.setBehavior({ mode: "hover", placement: "docked" });
                const fallbackBehavior = surface.setBehavior({ mode: "invalid", placement: "invalid" });
                const linkedTitleOk = surface.showContent({
                    heading: "Linked title",
                    headingHref: "Preview-Relationships/#--informal-preview-used_target--statement",
                    headingTitle: "Definition 6.1",
                    html: "<p>Preview body</p>",
                    allowEmpty: true
                }) && panel.querySelector(".bp_test_title a") &&
                    panel.querySelector(".bp_test_title a").getAttribute("href") ===
                        "Preview-Relationships/#--informal-preview-used_target--statement" &&
                    panel.querySelector(".bp_test_title a").getAttribute("title") === "Definition 6.1" &&
                    panel.querySelector(".bp_test_title a").textContent === "Linked title";
                panel.remove();
                return (
                    defaultBehavior.mode === "pinned" &&
                    defaultBehavior.placement === "anchored" &&
                    defaultBehavior.isPinned &&
                    defaultBehavior.isAnchored &&
                    panelBehavior.mode === "hover" &&
                    panelBehavior.placement === "docked" &&
                    panelBehavior.isHover &&
                    panelBehavior.isDocked &&
                    fallbackBehavior.mode === "hover" &&
                    fallbackBehavior.placement === "docked" &&
                    fallbackBehavior.isHover &&
                    fallbackBehavior.isDocked &&
                    linkedTitleOk
                );
                """
            )
        )

    def test_graph_preview_can_switch_to_hover_autohide(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        options_button = page.locator(".bp_graph_options_button").first
        preview_selector = page.locator(".bp_graph_preview_mode_select").first
        placement_selector = page.locator(".bp_graph_preview_placement_select").first
        panel = page.locator(".bp_graph_preview").first
        node = first_preview_node(page)

        options_button.click()
        expect(placement_selector).to_have_value("docked")
        preview_selector.select_option("hover")
        page.locator(".bp_graph_options_popover_close").first.click()

        page.wait_for_function(
            """() => {
                const panel = document.querySelector(".bp_graph_preview");
                const selector = document.querySelector(".bp_graph_preview_mode_select");
                return (
                    !!panel &&
                    !!selector &&
                    panel.hidden &&
                    selector.value === "hover" &&
                    panel.getAttribute("data-bp-preview-mode") === "hover" &&
                    panel.getAttribute("data-bp-preview-placement") === "docked"
                );
            }"""
        )

        node.hover()
        page.wait_for_function(
            """() => {
                const panel = document.querySelector(".bp_graph_preview");
                return !!panel && !panel.hidden;
            }"""
        )
        page.mouse.move(1390, 890)
        page.wait_for_function(
            """() => {
                const panel = document.querySelector(".bp_graph_preview");
                return !!panel && panel.hidden;
            }"""
        )

        options_button.click()
        placement_selector.select_option("anchored")
        page.locator(".bp_graph_options_popover_close").first.click()
        page.wait_for_function(
            """() => {
                const panel = document.querySelector(".bp_graph_preview");
                const selector = document.querySelector(".bp_graph_preview_placement_select");
                return (
                    !!panel &&
                    !!selector &&
                    panel.hidden &&
                    selector.value === "anchored" &&
                    panel.getAttribute("data-bp-preview-mode") === "hover" &&
                    panel.getAttribute("data-bp-preview-placement") === "anchored"
                );
            }"""
        )

    def test_graph_page_does_not_force_extra_vertical_scroll(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        metrics = page.evaluate(
            """() => ({
                scrollHeight: document.documentElement.scrollHeight,
                viewportHeight: window.innerHeight,
            })"""
        )

        assert metrics["scrollHeight"] - metrics["viewportHeight"] <= 2

    def test_graph_aligns_with_local_content_frame(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        metrics = page.evaluate(
            """() => {
                const graph = document.querySelector(".bp_graph_fullwidth");
                const wrapper = document.querySelector(".content-wrapper");
                const section = document.querySelector("main > .content-wrapper > section");
                if (!graph || !wrapper || !section) return null;
                const graphRect = graph.getBoundingClientRect();
                const wrapperRect = wrapper.getBoundingClientRect();
                const sectionRect = section.getBoundingClientRect();
                const wrapperStyle = getComputedStyle(wrapper);
                const paddingRight = parseFloat(wrapperStyle.paddingRight) || 0;
                return {
                    graphLeft: graphRect.left,
                    graphRight: graphRect.right,
                    sectionLeft: sectionRect.left,
                    wrapperRight: wrapperRect.right,
                    paddingRight,
                };
            }"""
        )

        assert metrics is not None
        assert abs(metrics["graphLeft"] - metrics["sectionLeft"]) < 4
        assert abs(metrics["graphRight"] - (metrics["wrapperRight"] - metrics["paddingRight"])) < 4
        assert metrics["graphRight"] - metrics["graphLeft"] > 950

    def test_graph_content_is_visible_near_top_of_canvas(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        assert_graph_is_well_placed(page)

    def test_graph_remains_well_placed_after_variant_switch(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        selector = page.locator(".bp_graph_view_select").first

        assert_graph_is_well_placed(page)

        for variant in ["group", "parent:preview_core", "parent:preview_group", "full"]:
            selector.select_option(variant)
            page.wait_for_function(
                """(expectedValue) => {
                    const select = document.querySelector(".bp_graph_view_select");
                    const canvas = document.querySelector(".bp_graph_canvas");
                    const svg = canvas ? canvas.querySelector("svg") : null;
                    return !!select && !!svg && select.value === expectedValue;
                }""",
                arg=variant,
            )
            assert_graph_is_well_placed(page)

    def test_graph_remains_interactive_after_variant_switch(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        selector = page.locator(".bp_graph_view_select").first

        assert_graph_has_zoom_handlers(page)
        assert_graph_can_be_dragged(page)

        for variant in ["group", "parent:preview_core", "full"]:
            selector.select_option(variant)
            wait_for_rendered_variant(page, variant)
            assert_graph_has_zoom_handlers(page)
            assert_graph_can_be_dragged(page)

    def test_graph_width_is_css_driven_without_inline_offsets(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        graph = page.locator(".bp_graph_fullwidth").first

        def style_snapshot():
            return graph.evaluate(
                """(el) => ({
                    left: el.style.left || "",
                    width: el.style.width || "",
                    maxWidth: el.style.maxWidth || "",
                })"""
            )

        initial_style = style_snapshot()
        assert initial_style == {"left": "", "width": "", "maxWidth": ""}

        initial_width = graph.evaluate("el => el.getBoundingClientRect().width")
        page.set_viewport_size({"width": 1180, "height": 900})
        page.wait_for_function(
            """(previousWidth) => {
                const graph = document.querySelector(".bp_graph_fullwidth");
                return !!graph && graph.getBoundingClientRect().width < previousWidth - 100;
            }""",
            arg=initial_width,
        )
        resized_style = style_snapshot()
        assert resized_style == {"left": "", "width": "", "maxWidth": ""}

    def test_graph_reflows_with_viewport_width_change(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        graph = page.locator(".bp_graph_fullwidth").first

        width_wide = graph.evaluate("el => el.getBoundingClientRect().width")
        page.set_viewport_size({"width": 1180, "height": 900})
        page.wait_for_function(
            """(previousWidth) => {
                const graph = document.querySelector(".bp_graph_fullwidth");
                return !!graph && graph.getBoundingClientRect().width < previousWidth - 100;
            }""",
            arg=width_wide,
        )
        width_narrow = graph.evaluate("el => el.getBoundingClientRect().width")

        assert width_narrow < width_wide - 100

        page.set_viewport_size({"width": 1400, "height": 900})
        page.wait_for_function(
            """(expectedWidth) => {
                const graph = document.querySelector(".bp_graph_fullwidth");
                if (!graph) return false;
                return Math.abs(graph.getBoundingClientRect().width - expectedWidth) < 8;
            }""",
            arg=width_wide,
        )

    def test_manual_canvas_height_survives_variant_switch(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        goto_graph_page(page, f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        canvas = page.locator(".bp_graph_canvas").first
        selector = page.locator(".bp_graph_view_select").first

        desired_height = canvas.evaluate(
            """(el) => {
                const style = getComputedStyle(el);
                const currentHeight = el.getBoundingClientRect().height;
                const maxHeight = parseFloat(style.maxHeight) || currentHeight;
                const desired = Math.max(300, Math.min(maxHeight - 10, currentHeight + 40));
                el.style.height = `${desired}px`;
                return desired;
            }"""
        )
        page.wait_for_function(
            """(desiredHeight) => {
                const canvas = document.querySelector(".bp_graph_canvas");
                if (!canvas) return false;
                return Math.abs(canvas.getBoundingClientRect().height - desiredHeight) < 3;
            }""",
            arg=desired_height,
        )

        selector.select_option("group")
        page.wait_for_function(
            """(desiredHeight) => {
                const canvas = document.querySelector(".bp_graph_canvas");
                const select = document.querySelector(".bp_graph_view_select");
                if (!canvas || !select) return false;
                return select.value === "group" && Math.abs(canvas.getBoundingClientRect().height - desiredHeight) < 3;
            }""",
            arg=desired_height,
        )

        selector.select_option("full")
        page.wait_for_function(
            """(desiredHeight) => {
                const canvas = document.querySelector(".bp_graph_canvas");
                const select = document.querySelector(".bp_graph_view_select");
                if (!canvas || !select) return false;
                return select.value === "full" && Math.abs(canvas.getBoundingClientRect().height - desiredHeight) < 3;
            }""",
            arg=desired_height,
        )

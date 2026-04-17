from playwright.sync_api import Page


def wait_for_graph(page: Page):
    page.wait_for_function(
        """() => {
            const canvas = document.querySelector(".bp_graph_canvas");
            const svg = canvas ? canvas.querySelector("svg") : null;
            return !!canvas && !!svg;
        }"""
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
            };
        }"""
    )


def assert_graph_is_well_placed(page: Page):
    metrics = graph_visibility_metrics(page)
    assert metrics is not None
    assert metrics["graphTop"] < metrics["canvasTop"] + 0.35 * metrics["canvasHeight"]
    assert metrics["graphBottom"] > metrics["canvasTop"] + 0.5 * metrics["canvasHeight"]


class TestGraphLayoutRuntime:
    def test_graph_legend_is_collapsed_by_default_and_tracks_variant_switch(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        page.goto(f"{server}/Dependency-Graph/")
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
        page.goto(f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        options_button = page.locator(".bp_graph_options_button").first
        options_panel = page.locator(".bp_graph_options_popover").first
        direction_selector = page.locator(".bp_graph_direction_select").first

        initial = graph_dimensions(page)
        assert initial is not None
        assert initial["activeDirection"] == "TB"

        options_button.click()
        page.wait_for_function(
            """() => {
                const button = document.querySelector(".bp_graph_options_button");
                const panel = document.querySelector(".bp_graph_options_popover");
                const select = document.querySelector(".bp_graph_direction_select");
                return (
                    !!button &&
                    !!panel &&
                    !!select &&
                    button.getAttribute("aria-expanded") === "true" &&
                    !panel.hidden &&
                    select.value === "TB"
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

        switched = graph_dimensions(page)
        assert switched is not None
        assert switched["activeDirection"] == "LR"
        assert switched["width"] > switched["height"]
        assert_graph_is_well_placed(page)

    def test_graph_page_does_not_force_extra_vertical_scroll(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        page.goto(f"{server}/Dependency-Graph/")
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
        page.goto(f"{server}/Dependency-Graph/")
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
        page.goto(f"{server}/Dependency-Graph/")
        wait_for_graph(page)

        assert_graph_is_well_placed(page)

    def test_graph_remains_well_placed_after_variant_switch(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        page.goto(f"{server}/Dependency-Graph/")
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

    def test_graph_width_is_css_driven_without_inline_offsets(self, server: str, page: Page):
        page.set_viewport_size({"width": 1400, "height": 900})
        page.goto(f"{server}/Dependency-Graph/")
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
        page.goto(f"{server}/Dependency-Graph/")
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
        page.goto(f"{server}/Dependency-Graph/")
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

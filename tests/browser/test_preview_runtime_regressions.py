import json
import re
import urllib.request

from playwright.sync_api import expect, Locator, Page

from support import (
    assert_no_runtime_errors,
    blueprint_render_api_script,
    record_runtime_errors,
    wait_for_blueprint_render_api,
)
from tests.preview_runtime_api import runtime_api_methods


def require_box(locator: Locator):
    box = locator.bounding_box()
    assert box is not None
    return box


class TestPreviewRuntimeRegressions:
    def test_public_xref_excludes_internal_blueprint_indexes(self, server: str):
        with urllib.request.urlopen(f"{server}/xref.json") as response:
            data = json.load(response)

        def has_domain(name: str) -> bool:
            return name in data or ("\u00ab" + name + "\u00bb") in data

        assert has_domain("Verso.Genre.Manual.section")
        assert has_domain("Informal.Block.informal")
        assert has_domain("Informal.Block.group")

        excluded = [
            "Informal.Block.informalCode",
            "Informal.Block.informalPreview",
            "Informal.Block.externalRenderedDecl",
            "Informal.Inline.bpCite.usages",
            "Informal.LeanCodePreview",
            "Informal.inlinePreview.store",
        ]
        assert not any(has_domain(name) for name in excluded)

        with urllib.request.urlopen(f"{server}/find/index.html") as response:
            find_html = response.read().decode("utf-8")
        for name in excluded:
            assert name not in find_html

    def test_highlighted_docstrings_read_text_content_without_layout_flush(self, server: str):
        with urllib.request.urlopen(f"{server}/Blueprint-Summary/") as response:
            html = response.read().decode("utf-8")

        assert "const str = d.innerText;" not in html
        assert 'const str = d.textContent || "";' in html

    def test_external_declaration_docstrings_render_markdown(self, server: str, page: Page):
        page.goto(f"{server}/Code-Panels/")

        doc_def = page.locator(
            '[data-decl="PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedDefinition"]'
        ).first
        expect(doc_def).to_have_count(1)
        expect(doc_def).to_have_attribute("data-kind", "def")
        expect(doc_def.locator(".bp_external_decl_header_status").first).to_contain_text("complete")
        doc_def_header = doc_def.locator(".bp_external_decl_kicker").first
        expect(doc_def_header.locator(".bp_external_decl_kind").first).to_contain_text("def")
        expect(doc_def_header.locator("code")).to_have_count(0)
        expect(doc_def_header.locator(".bp_external_decl_header_meta")).to_have_count(0)
        expect(doc_def.locator(".bp_external_decl_body > div.docstring").first).to_contain_text(
            "The first documented preview definition"
        )

        unsafe_def = page.locator(
            '[data-decl="PreviewRuntimeShowcase.CodePanelDecls.previewExternalUnsafeDefinition"]'
        ).first
        expect(unsafe_def).to_have_attribute("data-kind", "def")
        unsafe_header = unsafe_def.locator(".bp_external_decl_kicker").first
        expect(unsafe_header.locator(".bp_external_decl_kind").first).to_contain_text("def")
        expect(unsafe_header.locator(".bp_external_decl_header_meta").first).to_contain_text(
            "unsafe"
        )
        expect(unsafe_header.locator("code")).to_have_count(0)

        doc_fun = page.locator(
            '[data-decl="PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedFunction"]'
        ).first
        expect(doc_fun).to_have_count(1)
        fun_doc = doc_fun.locator(".bp_external_decl_body > div.docstring").first
        expect(fun_doc).to_contain_text("Adds a small preview offset")
        expect(fun_doc.locator("code").first).to_contain_text("n")

        decl = page.locator(
            '[data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage.ofCounterexample"]'
        ).first
        expect(decl).to_have_count(1)

        doc = decl.locator(".bp_external_decl_body > div.docstring").first
        expect(doc).to_be_visible()
        expect(doc).to_contain_text("Given a counterexample")
        expect(doc.locator("code").first).to_contain_text("a^p + b^p = c^p")
        expect(decl.locator(".bp_external_decl_body > pre.docstring")).to_have_count(0)

        stage = page.locator('[data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewStage"]').first
        expect(stage).to_have_attribute("data-kind", "inductive")
        expect(stage.locator(".bp_external_decl_header_status").first).to_contain_text("complete")
        expect(stage.locator(".bp_external_decl_kind").first).to_contain_text("inductive")
        expect(stage.locator(".bp_external_decl_kicker").first).to_contain_text("2 constructors")
        expect(stage.locator(".bp_external_decl_body").first).to_contain_text("Constructors")
        expect(stage.locator(".bp_external_decl_body").first).to_contain_text("The initial stage")
        expect(stage.locator(".bp_external_decl_source_path").first).to_have_attribute(
            "href",
            re.compile(
                r"https://github\.com/leanprover/verso-blueprint/blob/[0-9a-f]{40}/tests/test_blueprints/preview_runtime_showcase/PreviewRuntimeShowcase/Chapters/CodePanels\.lean#L\d+-L\d+$"
            ),
        )

        cls = page.locator('[data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewFold"]').first
        expect(cls).to_have_attribute("data-kind", "class")
        expect(cls.locator(".bp_external_decl_header_status").first).to_contain_text("complete")
        expect(cls.locator(".bp_external_decl_kind").first).to_contain_text("class")
        expect(cls.locator(".bp_external_decl_kicker").first).to_contain_text("2 methods")
        expect(cls.locator(".bp_external_decl_body").first).to_contain_text("Methods")
        expect(cls.locator(".bp_external_decl_body").first).to_contain_text("The neutral preview value")

    def test_issue_130_showcase_labels_external_decl_subsections_without_h1(
        self, server: str, page: Page
    ):
        page.goto(f"{server}/External-Declaration-Heading-Repro/Nested-External-Declaration-Panels/")

        expect(
            page.get_by_role("heading", name=re.compile("Nested External Declaration Panels"))
        ).to_be_visible()
        expect(page.locator(".bp_external_decl_body h1")).to_have_count(0)

        section_labels = page.locator(".bp_external_decl_section_label")
        expect(page.locator("p.bp_external_decl_section_label")).to_have_count(section_labels.count())
        labels = {label.strip() for label in section_labels.all_text_contents()}
        assert {"Fields", "Methods", "Constructors", "Extends"} <= labels

        groups = page.locator(".bp_external_decl_section[role='group'][aria-labelledby]")
        expect(groups).to_have_count(section_labels.count())

    def test_inline_docstringed_constructs_showcase(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Code-Panels/")

        body = page.locator("body")
        expect(body).to_contain_text("PanelInlineDocstringedStructure")
        expect(body).to_contain_text("Inline package docstring used to compare literate Lean")
        expect(body).to_contain_text("dependent-looking field")
        expect(body).to_contain_text("PanelInlineDocstringedStage")
        expect(body).to_contain_text("Inline workflow stage docstring used to compare")
        expect(body).to_contain_text("A follow-up inline stage carrying a counter.")
        expect(body).to_contain_text("PanelInlineMixedConfig")
        expect(body).to_contain_text("PanelInlineMixedState")
        expect(body).to_contain_text("PanelInlineMixedFold")
        expect(body).to_contain_text("Inline mixed fold class docstring.")

        structure_name = page.locator("#PanelInlineDocstringedStructure").first
        expect(structure_name).to_have_count(1)
        page.wait_for_function(
            """() => !!document.querySelector("#PanelInlineDocstringedStructure")?._tippy"""
        )
        assert page.evaluate("(el) => !!el._tippy", structure_name.element_handle())

        inline_code = structure_name.locator("xpath=ancestor::code[1]")
        expect(inline_code.locator(".doc-comment.token").first).to_contain_text("/--")
        expect(inline_code.locator("div.docstring")).to_have_count(0)
        expect(inline_code.locator("pre.docstring")).to_have_count(0)

        structure_name.hover()
        hover = page.locator(".tippy-box").last
        expect(hover).to_contain_text("PanelInlineDocstringedStructure")
        expect(hover.locator("li").first).to_contain_text("The field")
        expect(hover.locator("code").filter(has_text="left").first).to_be_visible()
        expect(hover.locator("strong").filter(has_text="Bold text").first).to_be_visible()
        assert not any("cloneNode" in err for err in errors), "\n".join(errors)

    def test_used_by_panel_loads_html_cache_only_when_opened(self, server: str, page: Page):
        attempts = {"count": 0}

        def count_cache_fetch(route):
            attempts["count"] += 1
            route.continue_()

        page.route("**/-verso-data/blueprint-html-cache.json", count_cache_fetch)
        page.goto(f"{server}/Preview-Relationships/")
        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()
        used_by_wrap = page.locator(
            '.bp_wrapper[title="used_target"] .bp_extra_slot_used_by .bp_relation_wrap'
        ).first
        used_by_wrap.wait_for()
        page.wait_for_timeout(250)

        # This intentionally uses the low-level status API: the regression is
        # about lazy cache fetch timing, not custom rendering.
        status = page.evaluate(
            blueprint_render_api_script("return api.readHtmlCacheStatus();")
        )
        assert attempts["count"] == 0
        assert status["state"] == "idle"

        used_by_wrap.locator(".bp_relation_chip").first.hover()
        page.wait_for_function(
            blueprint_render_api_script(
                'return api.readHtmlCacheStatus().state === "ready";'
            )
        )
        assert attempts["count"] == 1

    def test_html_cache_rejects_legacy_array_shape(self, server: str, page: Page):
        def legacy_array_cache(route):
            route.fulfill(
                status=200,
                body='[{"key":"used_source--statement","html":"<p>stale</p>"}]',
                content_type="application/json",
            )

        page.route("**/-verso-data/blueprint-html-cache.json", legacy_array_cache)
        page.goto(f"{server}/Preview-Relationships/")

        # Keep one direct cache-entry test so schema failures remain visible to
        # advanced clients that opt into explicit cache control.
        status = page.evaluate(
            blueprint_render_api_script(
                """
                await api.loadHtmlCacheEntry("used_source--statement");
                return api.readHtmlCacheStatus();
                """
            )
        )

        assert status["state"] == "error"
        assert "object with an entries array" in status["lastError"]

    def test_code_summary_preview_opens_from_keyboard_focus_for_nonlink_trigger(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")

        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        trigger = page.locator(
            '.bp_wrapper[title="used_target"] .bp_extra_slot_code .bp_code_summary_preview_wrap_active'
        ).first
        expect(trigger).to_have_count(1)
        expect(trigger).to_have_attribute("tabindex", "0")

        trigger.focus()

        panel = page.locator(".bp_code_summary_preview_panel").first
        expect(panel).to_be_visible()
        expect(panel.locator(".bp_code_summary_preview_title")).to_have_text("used_target")
        expect(panel.locator(".bp_code_decl_item")).to_have_count(1)
        expect(panel.locator(".bp_code_decl_item").first).to_contain_text("Nat.add")

        bbox = panel.bounding_box()
        viewport = page.viewport_size
        assert bbox is not None
        assert viewport is not None
        assert bbox["x"] >= 0
        assert bbox["y"] >= 0
        assert bbox["x"] + bbox["width"] <= viewport["width"]
        assert bbox["y"] + bbox["height"] <= viewport["height"]

        assert_no_runtime_errors(errors)

    def test_code_summary_decl_link_hover_loads_canonical_lean_preview(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Code-Panels/")

        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        wrapper = page.locator(
            '.bp_wrapper[title="panel_external_short_name_definition"]'
        ).first
        trigger = wrapper.locator(
            ".bp_extra_slot_code .bp_code_summary_preview_wrap_active"
        ).first
        expect(trigger).to_have_count(1)
        trigger.hover()

        summary_panel = page.locator(".bp_code_summary_preview_panel:not([hidden])").first
        expect(summary_panel).to_be_visible()
        expect(summary_panel.locator(".bp_code_summary_preview_title")).to_have_text(
            "panel_external_short_name_definition"
        )
        expect(summary_panel.locator(".bp_code_decl_item").first).to_contain_text(
            "previewExternalDefinition"
        )

        canonical_key = (
            "Informal.LeanCodePreview."
            "PreviewRuntimeShowcase.CodePanelDecls.previewExternalDefinition"
        )
        decl_link = summary_panel.locator(
            f'.bp_inline_preview_ref[data-bp-preview-key="{canonical_key}"]'
        ).first
        expect(decl_link).to_have_count(1)
        expect(decl_link.locator("code")).to_have_text("previewExternalDefinition")

        decl_link.hover()

        panel = page.locator("#bp-inline-preview-panel")
        body = panel.locator(".bp_inline_preview_panel_body")
        expect(panel).to_be_visible()
        expect(panel.locator(".bp_inline_preview_panel_title")).to_have_text(
            "previewExternalDefinition"
        )
        expect(body).to_contain_text(
            "PreviewRuntimeShowcase.CodePanelDecls.previewExternalDefinition"
        )
        expect(body).to_contain_text("def")

        assert_no_runtime_errors(errors)

    def test_blueprint_summary_decl_link_hover_loads_html_cache_backed_code_preview(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Blueprint-Summary/")

        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()
        page.locator("details").evaluate_all("els => els.forEach(el => { el.open = true; })")

        trigger = page.locator(
            '.bp_summary_decl_list .bp_inline_preview_ref[data-bp-preview-key^="Informal.LeanCodePreview"]'
        ).first
        expect(trigger).to_have_count(1)
        trigger.scroll_into_view_if_needed()
        trigger.hover()

        panel = page.locator("#bp-inline-preview-panel")
        body = panel.locator(".bp_inline_preview_panel_body")

        expect(panel).to_be_visible()
        expect(panel.locator(".bp_inline_preview_panel_title")).to_have_text(re.compile(r"^Lean declaration "))

        page.wait_for_function(
            """
            () => {
              const body = document.querySelector("#bp-inline-preview-panel .bp_inline_preview_panel_body");
              if (!body) return false;
              const html = body.innerHTML || "";
              const text = body.textContent || "";
              return html.trim().length > 0 && text.trim().length > 0;
            }
            """
        )

        assert body.inner_text().strip()
        assert body.inner_html().strip()

        assert_no_runtime_errors(errors)

    def test_exact_cache_keys_keep_statement_and_proof_previews_distinct(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")

        previews = page.evaluate(
            blueprint_render_api_script(
                """
                const statement = await api.resolvePreview("preview_facets--statement");
                const proof = await api.resolvePreview("preview_facets--proof");
                return {
                    statement: {
                        ok: statement.ok,
                        reason: statement.reason,
                        html: statement.html,
                        label: statement.manifestEntry ? statement.manifestEntry.label : null,
                        facet: statement.manifestEntry ? statement.manifestEntry.facet : null,
                        href: statement.manifestEntry ? statement.manifestEntry.href : null
                    },
                    proof: {
                        ok: proof.ok,
                        reason: proof.reason,
                        html: proof.html,
                        label: proof.manifestEntry ? proof.manifestEntry.label : null,
                        facet: proof.manifestEntry ? proof.manifestEntry.facet : null,
                        href: proof.manifestEntry ? proof.manifestEntry.href : null
                    }
                };
                """
            )
        )

        assert previews["statement"]["ok"]
        assert previews["statement"]["reason"] == ""
        assert previews["proof"]["ok"]
        assert previews["proof"]["reason"] == ""
        assert "Proof facet marker" in previews["proof"]["html"]
        assert "Proof facet marker" not in previews["statement"]["html"]
        assert "Statement facet marker" in previews["statement"]["html"]
        assert previews["statement"]["label"] == "preview_facets"
        assert previews["statement"]["facet"] == "statement"
        assert previews["proof"]["label"] == "preview_facets"
        assert previews["proof"]["facet"] == "proof"
        assert previews["statement"]["href"].startswith("Preview-Relationships/")
        assert "#--informal-preview-" in previews["statement"]["href"]
        assert previews["proof"]["href"].startswith("Preview-Relationships/")
        assert previews["proof"]["href"] != previews["statement"]["href"]
        assert previews["statement"]["href"].endswith("preview_facets--statement")
        assert previews["proof"]["href"].endswith("preview_facets--proof")
        assert "bp_label_preview_tpl" not in page.content()

        assert_no_runtime_errors(errors)

    def test_standalone_render_client_uses_public_render_api(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Custom-Render-Client/")

        client = page.locator("#custom-render-client-example").first
        expect(client).to_have_attribute("data-bp-custom-client-status", "ready")
        expect(client.locator("[data-bp-custom-client-example]")).to_have_count(8)
        expect(page.locator("body")).not_to_contain_text(
            "end PreviewRuntimeShowcase.Chapters.CustomRenderClient"
        )

        fragment_card = client.locator('[data-bp-custom-client-body="statement"]').locator(
            "xpath=ancestor::article[1]"
        ).first
        expect(fragment_card.locator("[data-bp-custom-client-title]").first).to_have_text(
            "Body fragment"
        )
        expect(fragment_card).to_have_attribute("data-bp-render-ok", "true")
        expect(fragment_card).to_have_attribute("data-bp-canonical-preview", "false")
        expect(fragment_card).to_have_attribute(
            "data-bp-preview-key", "preview_facets--statement"
        )
        expect(fragment_card).to_have_attribute("data-bp-manifest-label", "preview_facets")
        expect(fragment_card).to_have_attribute("data-bp-manifest-facet", "statement")
        statement_header = fragment_card.locator(
            "[data-bp-custom-client-preview-header]"
        ).first
        expect(statement_header).to_contain_text("Theorem")
        expect(statement_header).to_contain_text("facet statement")
        expect(statement_header).to_contain_text("preview_facets--statement")
        expect(statement_header.locator(".bp_custom_render_client_preview_title").first).to_have_attribute(
            "href", re.compile(r"Preview-Relationships/#--informal-preview-preview_facets--statement")
        )
        fragment_body = fragment_card.locator('[data-bp-custom-client-body="statement"]').first
        expect(fragment_body).to_contain_text("Statement facet marker")
        expect(fragment_body).not_to_contain_text("Proof facet marker")
        expect(fragment_body.locator(".bp_wrapper")).to_have_count(0)

        canonical_statement_card = client.locator(
            '[data-bp-custom-client-body="canonical-statement"]'
        ).locator("xpath=ancestor::article[1]").first
        expect(
            canonical_statement_card.locator("[data-bp-custom-client-title]").first
        ).to_have_text("Canonical statement")
        expect(canonical_statement_card).to_have_attribute("data-bp-render-ok", "true")
        expect(canonical_statement_card).to_have_attribute("data-bp-canonical-preview", "true")
        expect(
            canonical_statement_card.locator("[data-bp-custom-client-summary]").first
        ).to_be_hidden()
        canonical_statement_body = canonical_statement_card.locator(
            '[data-bp-custom-client-body="canonical-statement"]'
        ).first
        expect(canonical_statement_body.locator(".bp_wrapper").first).to_have_attribute(
            "title", "preview_facets"
        )
        expect(canonical_statement_body.locator(".bp_heading").first).to_contain_text("Theorem")
        expect(canonical_statement_body).to_contain_text("Statement facet marker")
        expect(canonical_statement_body).not_to_contain_text("Proof facet marker")

        proof_card = client.locator('[data-bp-preview-label="preview_facets"][data-bp-preview-facet="proof"]').first
        expect(proof_card.locator("[data-bp-custom-client-title]").first).to_have_text(
            "Canonical proof"
        )
        expect(proof_card).to_have_attribute("data-bp-render-ok", "true")
        expect(proof_card).to_have_attribute("data-bp-canonical-preview", "true")
        expect(proof_card.locator("[data-bp-custom-client-summary]").first).to_be_hidden()
        expect(proof_card).to_have_attribute("data-bp-preview-key", "preview_facets--proof")
        expect(proof_card).to_have_attribute("data-bp-manifest-label", "preview_facets")
        expect(proof_card).to_have_attribute("data-bp-manifest-facet", "proof")
        proof_body = proof_card.locator('[data-bp-custom-client-body="proof"]').first
        expect(proof_body.locator(".bp_wrapper").first).to_have_attribute(
            "title", "preview_facets"
        )
        expect(proof_body.locator(".bp_heading").first).to_contain_text("Proof for Theorem")
        expect(proof_body).to_contain_text("Proof facet marker")
        expect(proof_body).not_to_contain_text("Statement facet marker")

        used_by_card = client.locator('[data-bp-preview-label="used_target"]').first
        expect(used_by_card.locator("[data-bp-custom-client-title]").first).to_have_text(
            "Used-by and code"
        )
        expect(used_by_card).to_have_attribute("data-bp-render-ok", "true")
        expect(used_by_card).to_have_attribute("data-bp-canonical-preview", "true")
        expect(used_by_card).to_have_attribute("data-bp-manifest-title", re.compile(r"Definition"))
        expect(used_by_card.locator("[data-bp-custom-client-preview-header]")).to_be_hidden()
        expect(used_by_card.locator("[data-bp-custom-client-summary]").first).to_be_hidden()
        used_by_body = used_by_card.locator('[data-bp-custom-client-body="used-target"]').first
        expect(used_by_body.locator(".bp_wrapper").first).to_have_attribute("title", "used_target")
        expect(used_by_body.locator(".bp_extra_slot_used_by")).to_have_count(1)
        expect(used_by_body.locator(".bp_extra_slot_code")).to_have_count(1)
        expect(used_by_body).to_contain_text(
            "Target statement with associated Lean code"
        )

        group_card = client.locator('[data-bp-preview-label="group_target"]').first
        expect(group_card.locator("[data-bp-custom-client-title]").first).to_have_text(
            "Group header data"
        )
        expect(group_card).to_have_attribute("data-bp-render-ok", "true")
        expect(group_card).to_have_attribute("data-bp-canonical-preview", "true")
        expect(group_card.locator("[data-bp-custom-client-summary]").first).to_be_hidden()
        group_body = group_card.locator('[data-bp-custom-client-body="group-target"]').first
        expect(group_body.locator(".bp_extra_slot_group")).to_have_count(1)
        expect(group_body.locator(".bp_extra_slot_used_by")).to_have_count(1)

        grouped_statement_card = client.locator(
            '[data-bp-preview-label="used_grouped_proof_panel"][data-bp-preview-facet="statement"]'
        ).first
        expect(
            grouped_statement_card.locator("[data-bp-custom-client-title]").first
        ).to_have_text("Grouped theorem")
        expect(grouped_statement_card).to_have_attribute("data-bp-render-ok", "true")
        expect(grouped_statement_card).to_have_attribute("data-bp-canonical-preview", "true")
        expect(
            grouped_statement_card.locator("[data-bp-custom-client-summary]").first
        ).to_be_hidden()
        grouped_statement_body = grouped_statement_card.locator(
            '[data-bp-custom-client-body="grouped-statement"]'
        ).first
        expect(grouped_statement_body.locator(".bp_extra_slot_group")).to_have_count(1)
        expect(grouped_statement_body.locator(".bp_extra_slot_uses")).to_have_count(1)
        expect(grouped_statement_body.locator(".bp_extra_slot_used_by")).to_have_count(1)
        expect(grouped_statement_body.locator(".bp_extra_slot_code")).to_have_count(1)

        broken_custom_links = page.evaluate(
            """
            async () => {
                const links = Array.from(
                    document.querySelectorAll("#custom-render-client-example a[href]")
                );
                const broken = [];
                for (const link of links) {
                    const href = link.href;
                    const url = new URL(href);
                    if (url.origin !== location.origin) continue;
                    const response = await fetch(url.pathname + url.search);
                    if (!response.ok) {
                        broken.push({ href, reason: `HTTP ${response.status}` });
                        continue;
                    }
                    if (url.hash) {
                        let doc = document;
                        if (url.pathname !== location.pathname) {
                            const html = await response.text();
                            doc = new DOMParser().parseFromString(html, "text/html");
                        }
                        const id = decodeURIComponent(url.hash.slice(1));
                        if (!doc.getElementById(id)) {
                            broken.push({ href, reason: "missing anchor" });
                        }
                    }
                }
                return broken;
            }
            """
        )
        assert broken_custom_links == []

        missing_card = client.locator('[data-bp-preview-label="missing_custom_client_target"]').first
        expect(missing_card.locator("[data-bp-custom-client-title]").first).to_have_text(
            "Missing preview diagnostic"
        )
        expect(missing_card).to_have_attribute("data-bp-render-ok", "false")
        expect(missing_card).to_have_attribute("data-bp-expected-ok", "false")
        expect(missing_card).to_have_attribute("data-bp-canonical-preview", "false")
        expect(missing_card).to_have_attribute("data-bp-render-reason", "manifest-entry-missing")
        expect(missing_card.locator("[data-bp-custom-client-summary]").first).to_contain_text(
            "manifest-entry-missing"
        )
        missing_body = missing_card.locator('[data-bp-custom-client-body="missing"]').first
        expect(missing_body).to_contain_text("Preview entry missing from manifest")
        expect(missing_body).to_contain_text("missing_custom_client_target--statement")

        assert_no_runtime_errors(errors)

    def test_public_render_api_surface_keeps_state_private(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Custom-Render-Client/")

        stable_client_methods = runtime_api_methods("stableCustomClientApi")
        bundled_helper_methods = runtime_api_methods("bundledFeatureRenderHelpers")
        rendered = page.evaluate(
            blueprint_render_api_script(
                """
                const manifestStatus = api.readManifestStatus();
                const htmlCacheStatus = api.readHtmlCacheStatus();
                const mutatedManifestStatus = api.readManifestStatus();
                const mutatedHtmlCacheStatus = api.readHtmlCacheStatus();
                mutatedManifestStatus.state = "mutated";
                mutatedHtmlCacheStatus.state = "mutated";
                const stableClientMethods = __STABLE_CLIENT_METHODS__;
                const bundledHelperMethods = __BUNDLED_HELPER_METHODS__;
                return {
                    hasApi: true,
                    stableClientApiTypes: Object.fromEntries(
                        stableClientMethods.map((name) => [name, typeof api[name]])
                    ),
                    bundledHelperApiTypes: Object.fromEntries(
                        bundledHelperMethods.map((name) => [name, typeof api[name]])
                    ),
                    publicSurface: {
                        hasReadPreviewTemplate: typeof api.readPreviewTemplate === "function",
                        hasHydratePreviewSubtree: typeof api.hydratePreviewSubtree === "function",
                        hasRenderMath: typeof api.renderMath === "function",
                        hasReadManifestEntry: typeof api.readManifestEntry === "function",
                        hasReadHtmlCacheEntry: typeof api.readHtmlCacheEntry === "function",
                        hasBindCloseOnce: typeof api.bindCloseOnce === "function",
                        hasBindHoverablePanelLifetime: typeof api.bindHoverablePanelLifetime === "function",
                        hasBindTemplatePreview: typeof api.bindTemplatePreview === "function",
                        hasReadPanelBehavior: typeof api.readPanelBehavior === "function",
                        hasDiagnostics: typeof api.diagnostics !== "undefined",
                        hasReadHtml: typeof api.readHtml === "function"
                    },
                    removedGlobals: {
                        hasPreviewUtils: "bpPreviewUtils" in window,
                        hasPreviewHydrators: "bpPreviewHydrators" in window,
                        hasPreviewTrace: "bpPreviewTrace" in window,
                        hasManifestStatus: "bpBlueprintManifestStatus" in window,
                        hasManifestMap: "bpBlueprintManifest" in window,
                        hasManifestPromise: "bpBlueprintManifestPromise" in window,
                        hasManifestFile: "bpBlueprintManifestFile" in window,
                        hasHtmlCacheStatus: "bpBlueprintHtmlCacheStatus" in window,
                        hasHtmlCacheMap: "bpBlueprintHtmlCache" in window,
                        hasHtmlCachePromise: "bpBlueprintHtmlCachePromise" in window
                    },
                    manifestStatus: manifestStatus,
                    htmlCacheStatus: htmlCacheStatus,
                    manifestStatusAfterMutation: api.readManifestStatus(),
                    htmlCacheStatusAfterMutation: api.readHtmlCacheStatus()
                };
                """
                .replace("__STABLE_CLIENT_METHODS__", json.dumps(stable_client_methods))
                .replace("__BUNDLED_HELPER_METHODS__", json.dumps(bundled_helper_methods))
            )
        )

        assert rendered["hasApi"]
        assert set(rendered["stableClientApiTypes"].values()) == {"function"}
        assert set(rendered["bundledHelperApiTypes"].values()) == {"function"}
        assert rendered["publicSurface"] == {
            "hasReadPreviewTemplate": False,
            "hasHydratePreviewSubtree": False,
            "hasRenderMath": False,
            "hasReadManifestEntry": False,
            "hasReadHtmlCacheEntry": False,
            "hasBindCloseOnce": False,
            "hasBindHoverablePanelLifetime": False,
            "hasBindTemplatePreview": False,
            "hasReadPanelBehavior": False,
            "hasDiagnostics": False,
            "hasReadHtml": False,
        }
        assert rendered["removedGlobals"] == {
            "hasPreviewUtils": False,
            "hasPreviewHydrators": False,
            "hasPreviewTrace": False,
            "hasManifestStatus": False,
            "hasManifestMap": False,
            "hasManifestPromise": False,
            "hasManifestFile": False,
            "hasHtmlCacheStatus": False,
            "hasHtmlCacheMap": False,
            "hasHtmlCachePromise": False,
        }
        assert rendered["manifestStatus"]["state"] == "ready"
        assert rendered["htmlCacheStatus"]["state"] == "ready"
        assert rendered["manifestStatusAfterMutation"]["state"] == "ready"
        assert rendered["htmlCacheStatusAfterMutation"]["state"] == "ready"

        assert_no_runtime_errors(errors)

    def test_summary_preview_retries_after_html_cache_fetch_failure(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        attempts = {"count": 0}

        def fail_once(route):
            attempts["count"] += 1
            if attempts["count"] == 1:
                route.fulfill(
                    status=503,
                    body="preview HTML cache temporarily unavailable",
                    content_type="application/json",
                )
            else:
                route.continue_()

        page.route("**/-verso-data/blueprint-html-cache.json", fail_once)
        page.goto(f"{server}/Blueprint-Summary/")
        wait_for_blueprint_render_api(page)

        cache = page.evaluate(
            blueprint_render_api_script(
                """
                const host = document.createElement("div");
                document.body.appendChild(host);
                const trigger = document.querySelector(
                    ".bp_summary_preview_wrap_active[data-bp-preview-key]"
                );
                const previewKey =
                    trigger instanceof Element
                        ? (trigger.getAttribute("data-bp-preview-key") || "").trim()
                        : "";
                const first = await api.renderPreviewInto(host, previewKey);
                const statusAfterFirst = api.readHtmlCacheStatus();
                const firstHtml = host.innerHTML;
                const second = await api.renderPreviewInto(host, previewKey);
                const statusAfterSecond = api.readHtmlCacheStatus();
                return {
                    previewKey: previewKey,
                    firstOk: first.ok,
                    firstReason: first.reason,
                    firstHtml: firstHtml,
                    secondOk: second.ok,
                    secondReason: second.reason,
                    secondHtml: host.innerHTML,
                    statusAfterFirst: statusAfterFirst,
                    statusAfterSecond: statusAfterSecond
                };
                """
            )
        )

        assert cache["previewKey"]
        assert not cache["firstOk"]
        assert cache["firstReason"] == "html-cache-entry-missing"
        assert "Preview HTML cache unavailable" in cache["firstHtml"]
        assert cache["statusAfterFirst"]["state"] == "error"
        assert "503" in cache["statusAfterFirst"]["lastError"]
        assert cache["secondOk"]
        assert cache["secondReason"] == ""
        assert "<p" in cache["secondHtml"]
        assert cache["statusAfterSecond"]["state"] == "ready"
        assert cache["statusAfterSecond"]["attempts"] >= 2
        assert attempts["count"] > 1
        assert_no_runtime_errors(errors)

    def test_used_by_panel_loads_html_cache_backed_preview(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")

        wrap = page.locator('.bp_wrapper[title="used_target"] .bp_relation_wrap').first
        expect(wrap).to_have_count(1)
        assert "bp_relation_preview_fallback_tpl" not in page.content()

        chip = wrap.locator(".bp_relation_chip").first
        chip.hover()

        expect(wrap.locator(".bp_relation_panel .bp_relation_panel_meta")).to_have_text(
            "Reverse dependency previews"
        )
        expect(wrap.locator(".bp_relation_item.bp_relation_item_active")).to_have_count(1)

        header_label = wrap.locator(".bp_relation_preview_header_label")
        expect(header_label).to_be_visible()
        expect(header_label).to_contain_text("used_statement")
        expect(header_label).to_have_attribute("href", re.compile(r"#--informal-preview-used_statement"))

        body = wrap.locator(".bp_relation_preview_body")
        page.wait_for_function(
            "(el) => !!el && el.innerHTML.includes('<p')",
            arg=body.element_handle(),
        )
        expect(body).to_contain_text("Statement depends on")

        second_item = wrap.locator(".bp_relation_item").nth(1)
        second_item.hover()
        expect(second_item).to_have_class(re.compile(r"bp_relation_item_active"))
        expect(header_label).to_contain_text("used_proof")
        expect(header_label).to_have_attribute("href", re.compile(r"#--informal-preview-used_proof"))
        page.wait_for_function(
            "(el) => !!el && el.textContent.includes('Statement facet marker for preview relationships.')",
            arg=body.element_handle(),
        )
        expect(body).to_contain_text("Statement facet marker for preview relationships.")

        assert_no_runtime_errors(errors)

    def test_uses_single_dependency_loads_manifest_backed_inline_preview(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")
        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        slot = page.locator('.bp_wrapper[title="used_statement"] .bp_extra_slot_uses').first
        trigger = slot.locator(".bp_inline_preview_ref").first
        expect(trigger).to_have_count(1)
        expect(slot.locator(".bp_relation_wrap")).to_have_count(0)
        expect(slot.locator(".bp_relation_panel")).to_have_count(0)
        assert "bp_relation_preview_fallback_tpl" not in page.content()

        chip = trigger.locator(".bp_relation_chip").first
        expect(chip).to_have_text("uses 1")
        expect(trigger).to_have_attribute("data-bp-preview-id", re.compile(r"^bp-uses-"))
        expect(trigger).to_have_attribute("data-bp-preview-key", re.compile(r"used_target"))
        trigger.hover()

        panel = page.locator("#bp-inline-preview-panel")
        expect(panel).to_be_visible()

        body = panel.locator(".bp_inline_preview_panel_body")
        page.wait_for_function(
            "(el) => !!el && el.innerHTML.includes('<p')",
            arg=body.element_handle(),
        )
        expect(body).to_contain_text("Target statement with associated Lean code.")

        header_label = panel.locator(".bp_inline_preview_panel_label")
        expect(header_label).to_be_visible()
        expect(header_label).to_contain_text("used_target")
        expect(header_label).to_have_attribute("href", re.compile(r"#--informal-preview-used_target"))

        footer = panel.locator(".bp_inline_preview_panel_footer")
        expect(footer).to_be_visible()
        expect(footer).to_contain_text("statement")

        page.mouse.move(0, 0)
        expect(panel).to_be_hidden(timeout=1000)

        assert_no_runtime_errors(errors)

    def test_proof_uses_single_dependency_loads_from_proof_header(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")
        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        statement = page.locator(
            '.bp_wrapper.bp_kind_theorem_wrapper[title="used_proof"]'
        ).first
        statement_uses = statement.locator(".bp_extra_slot_uses .bp_relation_chip").first
        expect(statement_uses).to_have_text("uses 0")

        proof = page.locator('.bp_wrapper.bp_kind_proof_wrapper[title="used_proof"]').first
        slot = proof.locator(".bp_extra_slot_uses").first
        trigger = slot.locator(".bp_inline_preview_ref").first
        expect(trigger).to_have_count(1)
        expect(proof.locator(".bp_extra_slot_used_by")).to_have_count(0)
        expect(proof.locator(".bp_extra_slot_code")).to_have_count(0)
        expect(slot.locator(".bp_relation_wrap")).to_have_count(0)
        expect(slot.locator(".bp_relation_panel")).to_have_count(0)

        chip = trigger.locator(".bp_relation_chip").first
        expect(chip).to_have_text("uses 1")
        expect(trigger).to_have_attribute("data-bp-preview-id", re.compile(r"^bp-uses-"))
        expect(trigger).to_have_attribute("data-bp-preview-key", re.compile(r"used_target"))
        trigger.hover()

        panel = page.locator("#bp-inline-preview-panel")
        expect(panel).to_be_visible()

        body = panel.locator(".bp_inline_preview_panel_body")
        page.wait_for_function(
            "(el) => !!el && el.innerHTML.includes('<p')",
            arg=body.element_handle(),
        )
        expect(body).to_contain_text("Target statement with associated Lean code.")

        header_label = panel.locator(".bp_inline_preview_panel_label")
        expect(header_label).to_be_visible()
        expect(header_label).to_contain_text("used_target")
        expect(header_label).to_have_attribute("href", re.compile(r"#--informal-preview-used_target"))

        footer = panel.locator(".bp_inline_preview_panel_footer")
        expect(footer).to_be_visible()
        expect(footer).to_contain_text("proof")

        page.mouse.move(0, 0)
        expect(panel).to_be_hidden(timeout=1000)

        assert_no_runtime_errors(errors)

    def test_proof_uses_multiple_dependencies_loads_panel_previews(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")
        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        statement = page.locator(
            '.bp_wrapper.bp_kind_theorem_wrapper[title="used_proof_panel"]'
        ).first
        statement_uses_chip = statement.locator(".bp_extra_slot_uses .bp_relation_chip").first
        expect(statement_uses_chip).to_have_text("uses 0")

        proof = page.locator(
            '.bp_wrapper.bp_kind_proof_wrapper[title="used_proof_panel"]'
        ).first
        slot = proof.locator(".bp_extra_slot_uses").first
        wrap = slot.locator(".bp_relation_wrap").first
        expect(wrap).to_have_count(1)
        expect(slot.locator(".bp_inline_preview_ref")).to_have_count(0)

        chip = wrap.locator("button.bp_relation_chip").first
        expect(chip).to_have_text("uses 2")
        statement_uses_box = require_box(statement_uses_chip)
        caption_box = require_box(proof.locator(".bp_caption").first)
        chip_box = require_box(chip)
        assert abs(statement_uses_box["x"] - chip_box["x"]) < 1
        assert abs((caption_box["y"] + caption_box["height"]) - (chip_box["y"] + chip_box["height"])) < 1
        chip.hover()

        expect(wrap.locator(".bp_relation_panel .bp_relation_panel_title")).to_have_text(
            "Proof uses 2"
        )
        expect(wrap.locator(".bp_relation_panel .bp_relation_panel_meta")).to_have_text(
            "Proof dependency previews"
        )
        expect(wrap.locator(".bp_relation_badge_proof").first).to_be_visible()

        header_label = wrap.locator(".bp_relation_preview_header_label")
        expect(header_label).to_be_visible()
        expect(header_label).to_contain_text("used_target")
        expect(header_label).to_have_attribute("href", re.compile(r"#--informal-preview-used_target"))

        body = wrap.locator(".bp_relation_preview_body")
        page.wait_for_function(
            "(el) => !!el && el.textContent.includes('Target statement with associated Lean code.')",
            arg=body.element_handle(),
        )

        second_item = wrap.locator(".bp_relation_item").nth(1)
        second_item.hover()
        expect(second_item).to_have_class(re.compile(r"bp_relation_item_active"))
        expect(header_label).to_contain_text("used_aux_target")
        expect(header_label).to_have_attribute("href", re.compile(r"#--informal-preview-used_aux_target"))
        page.wait_for_function(
            "(el) => !!el && el.textContent.includes('Auxiliary target statement for multi-use proof previews.')",
            arg=body.element_handle(),
        )

        assert_no_runtime_errors(errors)

    def test_grouped_statement_and_proof_uses_columns_align(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")
        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        statement = page.locator(
            '.bp_wrapper.bp_kind_theorem_wrapper[title="used_grouped_proof_panel"]'
        ).first
        expect(statement.locator(".bp_extra_slot_group .bp_relation_chip").first).to_have_text(
            "group"
        )
        statement_uses_chip = statement.locator(".bp_extra_slot_uses .bp_relation_chip").first
        expect(statement_uses_chip).to_have_text("uses 0")
        expect(statement.locator(".bp_extra_slot_used_by .bp_relation_chip").first).to_have_text(
            "used by 1"
        )
        expect(statement.locator(".bp_extra_slot_code .bp_code_link")).to_have_count(1)

        proof = page.locator(
            '.bp_wrapper.bp_kind_proof_wrapper[title="used_grouped_proof_panel"]'
        ).first
        expect(proof.locator(".bp_extra_slot_group")).to_have_count(0)
        expect(proof.locator(".bp_extra_slot_used_by")).to_have_count(0)
        expect(proof.locator(".bp_extra_slot_code")).to_have_count(0)

        chip = proof.locator(".bp_extra_slot_uses .bp_relation_chip").first
        expect(chip).to_have_text("uses 2")

        group_box = require_box(statement.locator(".bp_extra_slot_group").first)
        statement_uses_box = require_box(statement_uses_chip)
        used_by_box = require_box(statement.locator(".bp_extra_slot_used_by").first)
        code_box = require_box(statement.locator(".bp_extra_slot_code").first)
        proof_caption_box = require_box(proof.locator(".bp_caption").first)
        proof_uses_box = require_box(chip)

        assert group_box["x"] < statement_uses_box["x"] < used_by_box["x"] < code_box["x"]
        assert abs(statement_uses_box["x"] - proof_uses_box["x"]) < 1
        assert abs(
            (proof_caption_box["y"] + proof_caption_box["height"])
            - (proof_uses_box["y"] + proof_uses_box["height"])
        ) < 1

        assert_no_runtime_errors(errors)

    def test_bibliography_hover_does_not_throw_and_opens_panel(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Inline-Hover-Previews/")

        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        trigger = page.locator(
            '.bp_inline_preview_ref[data-bp-preview-title="Bibliography: preview.showcase.cite"]'
        ).first
        expect(trigger).to_have_count(1)
        assert "bp_inline_preview_tpl" not in page.content()

        trigger.hover()

        panel = page.locator("#bp-inline-preview-panel")
        expect(panel).to_be_visible()
        body = panel.locator(".bp_inline_preview_panel_body")
        expect(body).to_contain_text("Preview showcase citation")
        expect(body).to_contain_text("Locator")

        assert_no_runtime_errors(errors)

    def test_nested_inline_subhover_uses_child_panel(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Inline-Hover-Previews/")

        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        outer = page.locator(
            '.bp_inline_preview_ref[data-bp-preview-key="nested_outer--statement"]'
        ).first
        expect(outer).to_have_count(1)

        outer.hover()

        main_panel = page.locator("#bp-inline-preview-panel")
        expect(main_panel).to_be_visible()

        nested = main_panel.locator(
            '.bp_inline_preview_panel_body .bp_inline_preview_ref[data-bp-preview-key="nested_inner--statement"]'
        ).first
        expect(nested).to_have_count(1)

        nested.hover()

        child_panel = page.locator("#bp-inline-preview-child-panel")
        expect(child_panel).to_be_visible()
        expect(child_panel.locator(".bp_inline_preview_panel_body")).to_contain_text(
            "Nested inner preview definition."
        )
        expect(main_panel.locator(".bp_inline_preview_panel_body")).to_contain_text(
            "Outer theorem refers to"
        )

        assert_no_runtime_errors(errors)

import re

from playwright.sync_api import expect, Page

from support import assert_no_runtime_errors, record_runtime_errors


class TestPreviewRuntimeRegressions:
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

        panel = page.locator(
            '.bp_wrapper[title="used_target"] .bp_extra_slot_code .bp_code_summary_preview_panel'
        ).first
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

    def test_blueprint_summary_decl_link_hover_loads_manifest_backed_code_preview(
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

    def test_exact_manifest_keys_keep_statement_and_proof_previews_distinct(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")

        previews = page.evaluate(
            """async () => {
                const utils = window.bpPreviewUtils;
                const statement = await utils.loadSharedPreviewEntry("preview_facets--statement");
                const proof = await utils.loadSharedPreviewEntry("preview_facets--proof");
                return {
                    statement: {
                        html: utils.readPreviewTemplate(statement),
                        label: statement ? statement.label : null,
                        facet: statement ? statement.facet : null,
                        href: statement ? statement.href : null
                    },
                    proof: {
                        html: utils.readPreviewTemplate(proof),
                        label: proof ? proof.label : null,
                        facet: proof ? proof.facet : null,
                        href: proof ? proof.href : null
                    }
                };
            }"""
        )

        assert "Proof facet marker" in previews["proof"]["html"]
        assert "Proof facet marker" not in previews["statement"]["html"]
        assert "Statement facet marker" in previews["statement"]["html"]
        assert previews["statement"]["label"] == "preview_facets"
        assert previews["statement"]["facet"] == "statement"
        assert previews["proof"]["label"] == "preview_facets"
        assert previews["proof"]["facet"] == "proof"
        assert previews["statement"]["href"].startswith("Preview-Relationships/")
        assert "#--informal-preview-" in previews["statement"]["href"]
        assert previews["proof"]["href"] == previews["statement"]["href"]
        assert "bp_label_preview_tpl" not in page.content()

        assert_no_runtime_errors(errors)

    def test_summary_preview_retries_after_manifest_fetch_failure(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        attempts = {"count": 0}

        def fail_once(route):
            attempts["count"] += 1
            if attempts["count"] == 1:
                route.fulfill(
                    status=503,
                    body="preview manifest temporarily unavailable",
                    content_type="application/json",
                )
            else:
                route.continue_()

        page.route("**/-verso-data/blueprint-preview-manifest.json", fail_once)
        page.goto(f"{server}/Blueprint-Summary/")

        manifest = page.evaluate(
            """async () => {
                const utils = window.bpPreviewUtils;
                const trigger = document.querySelector(
                    ".bp_summary_preview_wrap_active[data-bp-preview-key]"
                );
                const previewKey =
                    trigger instanceof Element
                        ? (trigger.getAttribute("data-bp-preview-key") || "").trim()
                        : "";
                const first = await utils.loadSharedPreviewEntry(previewKey);
                const statusAfterFirst = utils.readSharedPreviewManifestStatus();
                const second = await utils.loadSharedPreviewEntry(previewKey);
                const statusAfterSecond = utils.readSharedPreviewManifestStatus();
                return {
                    previewKey: previewKey,
                    firstHtml: utils.readPreviewTemplate(first),
                    secondHtml: utils.readPreviewTemplate(second),
                    statusAfterFirst: statusAfterFirst,
                    statusAfterSecond: statusAfterSecond
                };
            }"""
        )

        assert manifest["previewKey"]
        assert manifest["firstHtml"] == ""
        assert manifest["statusAfterFirst"]["state"] == "error"
        assert "503" in manifest["statusAfterFirst"]["lastError"]
        assert "<p" in manifest["secondHtml"]
        assert manifest["statusAfterSecond"]["state"] == "ready"
        assert manifest["statusAfterSecond"]["attempts"] >= 2
        assert attempts["count"] >= 2
        assert_no_runtime_errors(errors)

    def test_used_by_panel_loads_manifest_backed_preview(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")

        wrap = page.locator('.bp_wrapper[title="used_target"] .bp_used_by_wrap').first
        expect(wrap).to_have_count(1)
        assert "bp_used_by_preview_tpl" not in page.content()

        chip = wrap.locator(".bp_used_by_chip").first
        chip.hover()

        expect(wrap.locator(".bp_used_by_item.bp_used_by_item_active")).to_have_count(1)

        body = wrap.locator(".bp_used_by_preview_body")
        page.wait_for_function(
            "(el) => !!el && el.innerHTML.includes('<p')",
            arg=body.element_handle(),
        )
        expect(body).to_contain_text("Statement depends on")

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

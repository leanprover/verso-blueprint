from playwright.sync_api import expect, Page

from support import assert_no_runtime_errors, record_runtime_errors


class TestBlueprintGroupPreview:
    def test_manifest_uses_shared_group_catalog(self, server: str, page: Page):
        page.goto(f"{server}/Group-Previews/")

        result = page.evaluate(
            """
            async () => {
              const data = await import("../-verso-data/api/data.mjs");
              const entry = await data.loadManifestEntry(
                data.statementPreviewKey("group_target")
              );
              const groups = await data.loadGroups();
              const group = await data.loadGroup(entry.parent);
              return {
                parent: entry.parent,
                hasEmbeddedGroup: Object.prototype.hasOwnProperty.call(entry, "group"),
                groupCount: groups.length,
                matchingGroupCount: groups.filter(
                  (candidate) => candidate.label === entry.parent
                ).length,
                groupLabel: group && group.label,
                groupTitle: group && group.title,
                memberLabels: group ? group.entries.map((member) => member.label) : []
              };
            }
            """
        )

        assert result["parent"] == "preview_group"
        assert result["hasEmbeddedGroup"] is False
        assert result["groupCount"] >= 1
        assert result["matchingGroupCount"] == 1
        assert result["groupLabel"] == "preview_group"
        assert result["groupTitle"] == "Preview group title."
        assert result["memberLabels"] == [
            "group_target",
            "group_peer_one",
            "group_peer_two",
        ]

    def test_group_chip_opens_panel_and_updates_preview(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Group-Previews/")

        wrapper = page.locator('.bp_wrapper[title="group_target"]').first
        group_slot = wrapper.locator(".bp_extra_slot_group")
        chip = group_slot.locator(".bp_relation_chip").first
        panel = group_slot.locator(".bp_relation_panel").first

        expect(group_slot).to_have_count(1)
        expect(chip).to_have_text("group")

        chip.click()
        expect(panel).to_be_visible()
        expect(panel.locator(".bp_relation_panel_title")).to_contain_text("Group: Preview group title.")
        expect(panel.locator(".bp_relation_panel_meta")).to_have_text("Group member previews")

        items = panel.locator(".bp_relation_item")
        expect(items).to_have_count(2)
        expect(panel.locator(".bp_relation_item.bp_relation_item_active")).to_have_count(1)
        expect(panel.locator(".bp_relation_preview_body")).to_contain_text("First peer in the same group.")
        items.nth(1).hover()

        expect(panel.locator(".bp_relation_preview_body")).to_contain_text("Second peer in the same group.")
        assert_no_runtime_errors(errors)

    def test_blocks_without_parent_do_not_render_group_chip(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Group-Previews/")

        wrapper = page.locator('.bp_wrapper[title="ungrouped_theorem"]').first

        expect(wrapper.locator(".bp_extra_slot_group")).to_have_count(0)
        assert_no_runtime_errors(errors)

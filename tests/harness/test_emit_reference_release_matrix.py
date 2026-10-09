from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from scripts.emit_reference_release_matrix import load_catalog
from scripts.blueprint_harness_projects import reference_release_payload


class ControllerReleasePolicyTests(unittest.TestCase):
    def test_new_controller_catalog_uses_its_release_policy_on_an_older_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target34 = {"id": "v4.34.0", "toolchain": "v4.34.1", "verso_ref": "v4.34.0",
                        "branch": "v4.34.0", "deploy_pages": True}
            target35 = {"id": "v4.35.0", "toolchain": "v4.35.0", "verso_ref": "v4.35.0",
                        "branch": "v4.35.0", "deploy_pages": True}
            local_policy = {"version": 2, "default_dev_branch": "v4.34.0",
                            "required_backport_branches": [], "release_targets": [target34]}
            (root / "branch-policy.json").write_text(json.dumps(local_policy))
            manifest = root / "controller-projects.json"
            manifest.write_text(json.dumps({"version": 2, "projects": [{
                "id": "template", "source": {"kind": "in_repo_project", "project_root": "project_template"},
                "targets": [{"release": "v4.34.0"}, {"release": "v4.35.0"}],
                "generate_command": ["lake", "exe", "vbp", "build"],
            }]}))
            with self.assertRaisesRegex(ValueError, "unknown release target `v4.35.0`"):
                load_catalog(manifest)
            policy = root / "controller-policy.json"
            policy.write_text(json.dumps({**local_policy, "default_dev_branch": "v4.35.0",
                                         "required_backport_branches": ["v4.34.0"],
                                         "release_targets": [target34, target35]}))
            catalog = load_catalog(manifest, policy)
            self.assertEqual([target.release_id for target in catalog.release_targets],
                             ["v4.34.0", "v4.35.0"])
            self.assertEqual(catalog.projects[0].project_root, "project_template")
            resolved = reference_release_payload(manifest, catalog, "v4.34.0", root)
            self.assertEqual(resolved["toolchain"], "v4.34.1")
            self.assertEqual(resolved["branch"], "v4.34.0")
            # Controller policy is authoritative; a truly undeclared release still fails.
            policy.write_text(json.dumps({**local_policy, "release_targets": [target35]}))
            with self.assertRaisesRegex(ValueError, "unknown release target `v4.34.0`"):
                load_catalog(manifest, policy)


if __name__ == "__main__":
    unittest.main()

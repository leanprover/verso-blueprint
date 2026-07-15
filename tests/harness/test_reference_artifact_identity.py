from __future__ import annotations

from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scripts.reference_artifact_identity import (
    IDENTITY_FILENAME,
    artifact_identity,
    expected_identities_from_matrix,
    identity_envelope,
    install_identity,
    validate_artifact_identity,
    validate_identity_envelope,
    write_json,
)


REVISION_A = "a" * 40
REVISION_B = "b" * 40


def project_manifest(release_id: str, project_id: str, *, ref: str = "source-ref") -> dict[str, object]:
    return {
        "version": 2,
        "release_targets": [
            {
                "id": release_id,
                "toolchain": release_id,
                "verso_ref": release_id,
                "branch": release_id,
                "deploy_pages": True,
            }
        ],
        "projects": [
            {
                "id": project_id,
                "source": {
                    "kind": "git_checkout",
                    "repository": f"https://example.com/{project_id}.git",
                    "project_root": ".",
                },
                "targets": [{"release": release_id, "ref": ref}],
                "generate_command": ["lake", "exe", "vbp", "build", "--output", "{output_dir}"],
            }
        ],
    }


def envelope(release_id: str, project_id: str, revision: str = REVISION_A) -> dict[str, object]:
    return identity_envelope(
        artifact_identity(
            project_manifest(release_id, project_id),
            release_id=release_id,
            project_id=project_id,
            generator_revision=revision,
        )
    )


class ReferenceArtifactIdentityTests(unittest.TestCase):
    def test_identity_digest_is_deterministic_and_tracks_exact_inputs(self) -> None:
        first = envelope("v4.32.0", "verso-flt")
        second = envelope("v4.32.0", "verso-flt")
        changed_revision = envelope("v4.32.0", "verso-flt", REVISION_B)
        changed_manifest = identity_envelope(
            artifact_identity(
                project_manifest("v4.32.0", "verso-flt", ref="other-source-ref"),
                release_id="v4.32.0",
                project_id="verso-flt",
                generator_revision=REVISION_A,
            )
        )

        self.assertEqual(first, second)
        self.assertNotEqual(first["sha256"], changed_revision["sha256"])
        self.assertNotEqual(first["sha256"], changed_manifest["sha256"])

    def test_identity_rejects_manifest_target_mismatches(self) -> None:
        manifest = project_manifest("v4.32.0", "verso-flt")

        with self.assertRaisesRegex(ValueError, "does not match manifest project"):
            artifact_identity(
                manifest,
                release_id="v4.32.0",
                project_id="noperthedron",
                generator_revision=REVISION_A,
            )
        with self.assertRaisesRegex(ValueError, "does not match manifest target"):
            artifact_identity(
                manifest,
                release_id="v4.30.0",
                project_id="verso-flt",
                generator_revision=REVISION_A,
            )

    def test_identity_rejects_digest_tampering_and_extra_fields(self) -> None:
        tampered = envelope("v4.32.0", "verso-flt")
        tampered["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "identity digest mismatch"):
            validate_identity_envelope(tampered, context="test artifact")

        extra = envelope("v4.32.0", "verso-flt")
        extra["unexpected"] = True
        with self.assertRaisesRegex(ValueError, "expected exactly"):
            validate_identity_envelope(extra, context="test artifact")

    def test_installed_identity_validates_only_against_an_exact_match(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            artifact_root = root / "site"
            artifact_root.mkdir()
            expected_path = root / "expected.json"
            stale_path = root / "stale.json"
            write_json(expected_path, envelope("v4.32.0", "verso-flt"))
            write_json(stale_path, envelope("v4.32.0", "verso-flt", REVISION_B))

            installed = install_identity(expected_path, artifact_root)
            validate_artifact_identity(expected_path, artifact_root)

            self.assertEqual(installed, artifact_root / IDENTITY_FILENAME)
            with self.assertRaisesRegex(ValueError, "does not match"):
                validate_artifact_identity(stale_path, artifact_root)

    def test_expected_matrix_uses_each_release_branch_revision_once(self) -> None:
        matrix = {
            "include": [
                {
                    "artifact_name": "reference-blueprints-release-v4.32.0__project__verso-flt",
                    "release_id": "v4.32.0",
                    "project_id": "verso-flt",
                    "branch": "v4.32.0",
                    "project_manifest": project_manifest("v4.32.0", "verso-flt"),
                },
                {
                    "artifact_name": "reference-blueprints-release-v4.32.0__project__noperthedron",
                    "release_id": "v4.32.0",
                    "project_id": "noperthedron",
                    "branch": "v4.32.0",
                    "project_manifest": project_manifest("v4.32.0", "noperthedron"),
                },
            ]
        }

        with patch(
            "scripts.reference_artifact_identity.resolve_branch_revision",
            return_value=REVISION_A,
        ) as resolve:
            expected = expected_identities_from_matrix(matrix, Path("."))

        resolve.assert_called_once_with(Path("."), "v4.32.0")
        self.assertEqual(expected["version"], 1)
        self.assertEqual(
            set(expected["artifacts"]),
            {
                "reference-blueprints-release-v4.32.0__project__verso-flt",
                "reference-blueprints-release-v4.32.0__project__noperthedron",
            },
        )


if __name__ == "__main__":
    unittest.main()

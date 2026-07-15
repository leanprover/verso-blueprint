from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from scripts.reference_artifact_identity import (
    IDENTITY_FILENAME,
    artifact_identity,
    identity_envelope,
    write_json,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
REVISION_A = "a" * 40
REVISION_B = "b" * 40


def artifact_envelope(release_id: str, project_id: str, revision: str = REVISION_A) -> dict[str, object]:
    manifest = {
        "version": 2,
        "release_targets": [{"id": release_id}],
        "projects": [{"id": project_id, "targets": [{"release": release_id}]}],
    }
    return identity_envelope(
        artifact_identity(
            manifest,
            release_id=release_id,
            project_id=project_id,
            generator_revision=revision,
        )
    )


class StageReferenceDeployArtifactsTests(unittest.TestCase):
    def run_helper(
        self,
        artifacts_root: Path,
        output_root: Path,
        expected_identities: Path,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                "scripts/stage_reference_deploy_artifacts.py",
                "--artifacts-root",
                str(artifacts_root),
                "--output-root",
                str(output_root),
                "--expected-identities",
                str(expected_identities),
            ],
            cwd=PACKAGE_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_stage_artifacts_rebuilds_release_project_tree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            artifacts_root = tmp_path / "reference-artifact-downloads"
            output_root = tmp_path / "reference-blueprints"
            expected_path = tmp_path / "expected.json"

            direct = artifacts_root / "reference-blueprints-release-v4.28.0__project__project-template"
            (direct / "html-multi").mkdir(parents=True)
            (direct / "html-multi" / "index.html").write_text("project template v4.28.0", encoding="utf-8")
            direct_identity = artifact_envelope("v4.28.0", "project-template")
            write_json(direct / IDENTITY_FILENAME, direct_identity)

            nested = artifacts_root / "reference-blueprints-release-v4.29.0__project__noperthedron"
            (nested / "noperthedron" / "html-multi").mkdir(parents=True)
            (nested / "noperthedron" / "html-multi" / "index.html").write_text(
                "noperthedron v4.29.0",
                encoding="utf-8",
            )
            nested_identity = artifact_envelope("v4.29.0", "noperthedron")
            write_json(nested / "noperthedron" / IDENTITY_FILENAME, nested_identity)
            write_json(
                expected_path,
                {
                    "version": 1,
                    "artifacts": {
                        direct.name: direct_identity,
                        nested.name: nested_identity,
                    },
                },
            )

            result = self.run_helper(artifacts_root, output_root, expected_path)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self.assertEqual(
                (output_root / "v4.28.0" / "project-template" / "html-multi" / "index.html").read_text(
                    encoding="utf-8"
                ),
                "project template v4.28.0",
            )
            self.assertEqual(
                (output_root / "v4.29.0" / "noperthedron" / "html-multi" / "index.html").read_text(
                    encoding="utf-8"
                ),
                "noperthedron v4.29.0",
            )
            self.assertFalse((output_root / "v4.28.0" / "project-template" / IDENTITY_FILENAME).exists())
            self.assertFalse((output_root / "v4.29.0" / "noperthedron" / IDENTITY_FILENAME).exists())

    def test_stage_artifacts_rejects_stale_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            artifacts_root = root / "artifacts"
            output_root = root / "output"
            expected_path = root / "expected.json"
            artifact = artifacts_root / "reference-blueprints-release-v4.32.0__project__verso-flt"
            (artifact / "html-multi").mkdir(parents=True)
            write_json(artifact / IDENTITY_FILENAME, artifact_envelope("v4.32.0", "verso-flt", REVISION_A))
            write_json(
                expected_path,
                {"version": 1, "artifacts": {artifact.name: artifact_envelope("v4.32.0", "verso-flt", REVISION_B)}},
            )

            result = self.run_helper(artifacts_root, output_root, expected_path)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not match the current catalog and release branch", result.stderr)

    def test_stage_artifacts_rejects_missing_and_unexpected_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            artifacts_root = root / "artifacts"
            output_root = root / "output"
            expected_path = root / "expected.json"
            expected_name = "reference-blueprints-release-v4.32.0__project__verso-flt"
            write_json(
                expected_path,
                {"version": 1, "artifacts": {expected_name: artifact_envelope("v4.32.0", "verso-flt")}},
            )
            artifacts_root.mkdir()

            missing = self.run_helper(artifacts_root, output_root, expected_path)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("missing deploy reference artifacts", missing.stderr)

            unexpected = artifacts_root / "reference-blueprints-release-v4.30.0__project__verso-carleson"
            (unexpected / "html-multi").mkdir(parents=True)
            write_json(unexpected / IDENTITY_FILENAME, artifact_envelope("v4.30.0", "verso-carleson"))

            extra = self.run_helper(artifacts_root, output_root, expected_path)
            self.assertNotEqual(extra.returncode, 0)
            self.assertIn("unexpected deploy reference artifact", extra.stderr)


if __name__ == "__main__":
    unittest.main()

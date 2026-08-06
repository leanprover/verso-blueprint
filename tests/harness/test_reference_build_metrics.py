from __future__ import annotations

import argparse
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

from scripts.reference_build_metrics import (
    DEFAULT_BASELINE_URL,
    compare_measurements,
    discover_measurements,
    load_json,
    parse_finished_phase,
    record_build,
    report_builds,
)


def measurement(
    project_id: str,
    *,
    source_ref: str = "abc",
    toolchain: str = "v4.33.0-rc1",
    traversal_ms: int = 1_000,
    command_ms: int = 10_000,
) -> dict[str, object]:
    return {
        "schema_version": 1,
        "project_id": project_id,
        "release_id": "v4.33.0",
        "source_ref": source_ref,
        "toolchain": toolchain,
        "recorded_at": "2026-08-06T00:00:00Z",
        "generator_revision": "def",
        "github_run_id": "1",
        "github_run_attempt": "1",
        "status": "success",
        "command_duration_ms": command_ms,
        "phases": [
            {"name": "multi-page HTML traversal", "duration_ms": traversal_ms},
            {"name": "emitting multi-page HTML", "duration_ms": 250},
        ],
    }


class TestReferenceBuildMetrics(unittest.TestCase):
    def test_parse_finished_phase_accepts_ansi_and_rejects_progress(self) -> None:
        self.assertEqual(
            parse_finished_phase("\x1b[32mBlueprint: finished multi-page HTML traversal in 1234ms\x1b[0m\n"),
            {"name": "multi-page HTML traversal", "duration_ms": 1234},
        )
        self.assertIsNone(parse_finished_phase("Blueprint: starting multi-page HTML traversal"))

    def test_record_build_tees_output_and_writes_structured_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "metrics.json"
            args = argparse.Namespace(
                output=str(output),
                project_id="verso-flt",
                release_id="v4.33.0",
                source_ref="abc",
                toolchain="v4.33.0-rc1",
                command=[
                    "--",
                    sys.executable,
                    "-c",
                    (
                        "print('ordinary output'); "
                        "print('Blueprint: finished multi-page HTML traversal in 4321ms')"
                    ),
                ],
            )
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                returncode = record_build(args)

            self.assertEqual(returncode, 0)
            self.assertIn("ordinary output", stdout.getvalue())
            data = load_json(output)
            self.assertEqual(data["project_id"], "verso-flt")
            self.assertEqual(data["status"], "success")
            self.assertEqual(
                data["phases"],
                [{"name": "multi-page HTML traversal", "duration_ms": 4321}],
            )
            self.assertGreaterEqual(data["command_duration_ms"], 0)

    def test_discover_measurements_rejects_duplicate_release_project(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for directory in (root / "one", root / "two"):
                directory.mkdir()
                (directory / "build-metrics.json").write_text(
                    json.dumps(measurement("verso-flt")),
                    encoding="utf-8",
                )
            with self.assertRaisesRegex(ValueError, "duplicate build metrics"):
                discover_measurements(root)

    def test_comparison_warns_only_for_same_source_and_toolchain(self) -> None:
        baseline = {
            "schema_version": 1,
            "measurements": [measurement("same"), measurement("changed")],
        }
        comparisons = compare_measurements(
            [
                measurement("same", traversal_ms=1_500),
                measurement("changed", source_ref="new", traversal_ms=1_500),
            ],
            baseline,
            regression_percent=20,
            regression_min_ms=250,
        )
        traversal = {
            (item["project_id"], item["phase"]): item
            for item in comparisons
            if item["phase"] == "multi-page HTML traversal"
        }
        self.assertTrue(traversal[("same", "multi-page HTML traversal")]["regression"])
        self.assertFalse(traversal[("changed", "multi-page HTML traversal")]["comparable"])
        self.assertFalse(traversal[("changed", "multi-page HTML traversal")]["regression"])

    def test_comparison_includes_total_generator_command(self) -> None:
        baseline = {
            "schema_version": 1,
            "measurements": [measurement("verso-flt", command_ms=10_000)],
        }
        comparisons = compare_measurements(
            [measurement("verso-flt", command_ms=13_000)],
            baseline,
            regression_percent=20,
            regression_min_ms=1_000,
        )

        command = next(item for item in comparisons if item["phase"] == "generator command")
        self.assertTrue(command["regression"])
        self.assertEqual(command["delta_ms"], 3_000)

    def test_report_writes_summary_comparison_and_history(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            artifact = root / "artifact"
            artifact.mkdir()
            (artifact / "build-metrics.json").write_text(
                json.dumps(measurement("verso-flt", traversal_ms=1_500)),
                encoding="utf-8",
            )
            baseline_path = root / "baseline.json"
            baseline_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "measurements": [measurement("verso-flt")],
                        "history": [{"generated_at": "earlier", "measurements": []}],
                    }
                ),
                encoding="utf-8",
            )
            output = root / "site" / "build-data.json"
            summary = root / "summary.md"
            args = argparse.Namespace(
                input_root=str(root),
                output=str(output),
                baseline=str(baseline_path),
                baseline_url=DEFAULT_BASELINE_URL,
                summary_output=str(summary),
                regression_percent=20.0,
                regression_min_ms=250,
                history_limit=50,
                fail_on_regression=False,
            )

            with contextlib.redirect_stdout(io.StringIO()):
                returncode = report_builds(args)

            self.assertEqual(returncode, 0)
            report = load_json(output)
            self.assertEqual(report["comparison"]["regression_count"], 1)
            self.assertEqual(len(report["history"]), 2)
            summary_text = summary.read_text(encoding="utf-8")
            self.assertIn("Reference Blueprint build timings", summary_text)
            self.assertIn("1.5s (+50.0%) ⚠", summary_text)


if __name__ == "__main__":
    unittest.main()

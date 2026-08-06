from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


SCHEMA_VERSION = 1
METRICS_FILENAME = "build-metrics.json"
DEFAULT_BASELINE_URL = (
    "https://leanprover.github.io/verso-blueprint/"
    "build-data/reference-blueprints.json"
)
DEFAULT_REGRESSION_PERCENT = 20.0
DEFAULT_REGRESSION_MIN_MS = 1_000
DEFAULT_HISTORY_LIMIT = 50

ANSI_ESCAPE_PATTERN = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
FINISHED_PHASE_PATTERN = re.compile(
    r"^Blueprint: finished (?P<name>.+) in (?P<duration_ms>[0-9]+)ms$"
)
TRAVERSAL_PHASES = (
    "single-page HTML traversal",
    "multi-page HTML traversal",
)
COMMAND_METRIC = "generator command"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def parse_finished_phase(line: str) -> dict[str, object] | None:
    normalized = ANSI_ESCAPE_PATTERN.sub("", line).strip()
    match = FINISHED_PHASE_PATTERN.fullmatch(normalized)
    if match is None:
        return None
    return {
        "name": match.group("name"),
        "duration_ms": int(match.group("duration_ms")),
    }


def _optional_text(value: str | None) -> str | None:
    if value is None or not value.strip():
        return None
    return value.strip()


def record_build(args: argparse.Namespace) -> int:
    command = list(args.command)
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        raise SystemExit("reference build metrics recorder requires a command after `--`")

    phases: list[dict[str, object]] = []
    started = time.monotonic_ns()
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    try:
        for line in process.stdout:
            print(line, end="", flush=True)
            phase = parse_finished_phase(line)
            if phase is not None:
                phases.append(phase)
    finally:
        process.stdout.close()
    returncode = process.wait()
    duration_ms = (time.monotonic_ns() - started) // 1_000_000

    measurement = {
        "schema_version": SCHEMA_VERSION,
        "project_id": args.project_id,
        "release_id": args.release_id,
        "source_ref": _optional_text(args.source_ref),
        "toolchain": _optional_text(args.toolchain),
        "recorded_at": utc_now(),
        "generator_revision": _optional_text(os.environ.get("GITHUB_SHA")),
        "github_run_id": _optional_text(os.environ.get("GITHUB_RUN_ID")),
        "github_run_attempt": _optional_text(os.environ.get("GITHUB_RUN_ATTEMPT")),
        "status": "success" if returncode == 0 else "failure",
        "command_duration_ms": duration_ms,
        "phases": phases,
    }
    output = Path(args.output)
    write_json(output, measurement)
    print(
        f"[reference-build-metrics] recorded {len(phases)} phases for "
        f"{args.release_id}/{args.project_id} in {output}",
        flush=True,
    )
    return returncode


def _require_string(value: object, field: str, *, context: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{context}: `{field}` must be a non-empty string")
    return value


def validate_measurement(value: object, *, context: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ValueError(f"{context}: expected a JSON object")
    if value.get("schema_version") != SCHEMA_VERSION:
        raise ValueError(f"{context}: unsupported build metrics schema")
    _require_string(value.get("project_id"), "project_id", context=context)
    _require_string(value.get("release_id"), "release_id", context=context)
    command_duration_ms = value.get("command_duration_ms")
    if not isinstance(command_duration_ms, int) or command_duration_ms < 0:
        raise ValueError(f"{context}: `command_duration_ms` must be a non-negative integer")
    phases = value.get("phases")
    if not isinstance(phases, list):
        raise ValueError(f"{context}: `phases` must be a list")
    for index, phase in enumerate(phases):
        phase_context = f"{context}: phase {index}"
        if not isinstance(phase, dict):
            raise ValueError(f"{phase_context} must be an object")
        _require_string(phase.get("name"), "name", context=phase_context)
        duration_ms = phase.get("duration_ms")
        if not isinstance(duration_ms, int) or duration_ms < 0:
            raise ValueError(f"{phase_context}: `duration_ms` must be a non-negative integer")
    return value


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def discover_measurements(input_root: Path) -> list[dict[str, object]]:
    measurements = [
        validate_measurement(load_json(path), context=str(path))
        for path in sorted(input_root.rglob(METRICS_FILENAME))
    ]
    if not measurements:
        raise ValueError(f"no `{METRICS_FILENAME}` files found under {input_root}")
    keys: set[tuple[str, str]] = set()
    for measurement in measurements:
        key = (str(measurement["release_id"]), str(measurement["project_id"]))
        if key in keys:
            raise ValueError(f"duplicate build metrics for {key[0]}/{key[1]}")
        keys.add(key)
    return sorted(measurements, key=lambda item: (str(item["release_id"]), str(item["project_id"])))


def load_baseline_file(path: Path) -> dict[str, object]:
    value = load_json(path)
    if not isinstance(value, dict) or value.get("schema_version") != SCHEMA_VERSION:
        raise ValueError(f"{path}: unsupported reference build report schema")
    return value


def load_baseline_url(url: str) -> tuple[dict[str, object] | None, str | None]:
    request = Request(url, headers={"User-Agent": "verso-blueprint-build-metrics"})
    try:
        with urlopen(request, timeout=15) as response:
            value = json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
        return None, str(error)
    if not isinstance(value, dict) or value.get("schema_version") != SCHEMA_VERSION:
        return None, "unsupported reference build report schema"
    return value, None


def measurement_key(measurement: dict[str, object]) -> tuple[str, str]:
    return str(measurement["release_id"]), str(measurement["project_id"])


def phase_durations(measurement: dict[str, object]) -> dict[str, int]:
    phases = measurement.get("phases")
    if not isinstance(phases, list):
        return {}
    return {
        str(phase["name"]): int(phase["duration_ms"])
        for phase in phases
        if isinstance(phase, dict)
        and isinstance(phase.get("name"), str)
        and isinstance(phase.get("duration_ms"), int)
    }


def metric_durations(measurement: dict[str, object]) -> dict[str, int]:
    metrics = phase_durations(measurement)
    command_duration_ms = measurement.get("command_duration_ms")
    if isinstance(command_duration_ms, int):
        return {COMMAND_METRIC: command_duration_ms, **metrics}
    return metrics


def measurements_comparable(current: dict[str, object], baseline: dict[str, object]) -> bool:
    return (
        current.get("source_ref") == baseline.get("source_ref")
        and current.get("toolchain") == baseline.get("toolchain")
    )


def compare_measurements(
    current: list[dict[str, object]],
    baseline_report: dict[str, object] | None,
    *,
    regression_percent: float,
    regression_min_ms: int,
) -> list[dict[str, object]]:
    if baseline_report is None:
        return []
    baseline_values = baseline_report.get("measurements")
    if not isinstance(baseline_values, list):
        return []
    baseline_by_key: dict[tuple[str, str], dict[str, object]] = {}
    for index, value in enumerate(baseline_values):
        try:
            baseline_measurement = validate_measurement(
                value,
                context=f"baseline measurement {index}",
            )
        except ValueError:
            continue
        baseline_by_key[measurement_key(baseline_measurement)] = baseline_measurement

    comparisons: list[dict[str, object]] = []
    for measurement in current:
        key = measurement_key(measurement)
        baseline = baseline_by_key.get(key)
        if baseline is None:
            continue
        comparable = measurements_comparable(measurement, baseline)
        baseline_metrics = metric_durations(baseline)
        for metric_name, current_ms in metric_durations(measurement).items():
            baseline_ms = baseline_metrics.get(metric_name)
            if baseline_ms is None:
                continue
            delta_ms = current_ms - baseline_ms
            delta_percent = None if baseline_ms == 0 else (delta_ms * 100.0 / baseline_ms)
            regression = bool(
                comparable
                and delta_ms >= regression_min_ms
                and delta_percent is not None
                and delta_percent >= regression_percent
            )
            comparisons.append(
                {
                    "release_id": key[0],
                    "project_id": key[1],
                    "phase": metric_name,
                    "current_ms": current_ms,
                    "baseline_ms": baseline_ms,
                    "delta_ms": delta_ms,
                    "delta_percent": delta_percent,
                    "comparable": comparable,
                    "regression": regression,
                }
            )
    return comparisons


def format_duration(duration_ms: int | None) -> str:
    if duration_ms is None:
        return "—"
    if duration_ms < 1_000:
        return f"{duration_ms}ms"
    seconds = duration_ms / 1_000.0
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes = int(seconds // 60)
    return f"{minutes}m{seconds - minutes * 60:04.1f}s"


def comparison_by_phase(comparisons: list[dict[str, object]]) -> dict[tuple[str, str, str], dict[str, object]]:
    return {
        (str(item["release_id"]), str(item["project_id"]), str(item["phase"])): item
        for item in comparisons
    }


def format_phase_cell(
    measurement: dict[str, object],
    phase_name: str,
    comparisons: dict[tuple[str, str, str], dict[str, object]],
) -> str:
    duration = metric_durations(measurement).get(phase_name)
    text = format_duration(duration)
    comparison = comparisons.get((*measurement_key(measurement), phase_name))
    if comparison is None:
        return text
    if not comparison["comparable"]:
        return f"{text} (source/toolchain changed)"
    delta_percent = comparison["delta_percent"]
    if delta_percent is None:
        return text
    marker = " ⚠" if comparison["regression"] else ""
    return f"{text} ({float(delta_percent):+.1f}%){marker}"


def markdown_report(
    measurements: list[dict[str, object]],
    comparisons: list[dict[str, object]],
    *,
    baseline_description: str,
    regression_percent: float,
    regression_min_ms: int,
) -> str:
    by_phase = comparison_by_phase(comparisons)
    lines = [
        "## Reference Blueprint build timings",
        "",
        f"Baseline: {baseline_description}",
        "",
        "| Release | Blueprint | `vbp build` | Single-page traversal | Multi-page traversal |",
        "|---|---|---:|---:|---:|",
    ]
    for measurement in measurements:
        lines.append(
            "| "
            + " | ".join(
                [
                    str(measurement["release_id"]),
                    str(measurement["project_id"]),
                    format_phase_cell(measurement, COMMAND_METRIC, by_phase),
                    format_phase_cell(measurement, TRAVERSAL_PHASES[0], by_phase),
                    format_phase_cell(measurement, TRAVERSAL_PHASES[1], by_phase),
                ]
            )
            + " |"
        )

    regressions = [item for item in comparisons if item["regression"]]
    lines.extend(
        [
            "",
            (
                "Regression warnings require both "
                f"+{regression_percent:g}% and +{format_duration(regression_min_ms)} "
                "against the same reference source and toolchain. Full command and phase data is retained in JSON."
            ),
        ]
    )
    if regressions:
        lines.extend(["", "Warnings:"])
        for item in regressions:
            lines.append(
                f"- {item['release_id']}/{item['project_id']} — {item['phase']}: "
                f"{format_duration(int(item['baseline_ms']))} → {format_duration(int(item['current_ms']))} "
                f"({float(item['delta_percent']):+.1f}%)"
            )
    return "\n".join(lines) + "\n"


def history_from_baseline(baseline: dict[str, object] | None) -> list[object]:
    if baseline is None:
        return []
    history = baseline.get("history")
    return list(history) if isinstance(history, list) else []


def report_builds(args: argparse.Namespace) -> int:
    input_root = Path(args.input_root)
    try:
        measurements = discover_measurements(input_root)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(str(error)) from error

    baseline: dict[str, object] | None = None
    baseline_description = "unavailable (first measurement or baseline fetch failed)"
    baseline_error: str | None = None
    if args.baseline is not None:
        try:
            baseline = load_baseline_file(Path(args.baseline))
            baseline_description = str(args.baseline)
        except (OSError, ValueError, json.JSONDecodeError) as error:
            baseline_error = str(error)
    elif args.baseline_url:
        baseline, baseline_error = load_baseline_url(args.baseline_url)
        if baseline is not None:
            baseline_description = args.baseline_url

    if baseline_error is not None:
        print(f"[reference-build-metrics] baseline unavailable: {baseline_error}", file=sys.stderr)

    comparisons = compare_measurements(
        measurements,
        baseline,
        regression_percent=args.regression_percent,
        regression_min_ms=args.regression_min_ms,
    )
    regressions = [item for item in comparisons if item["regression"]]
    generated_at = utc_now()
    snapshot = {
        "generated_at": generated_at,
        "generator_revision": _optional_text(os.environ.get("GITHUB_SHA")),
        "github_run_id": _optional_text(os.environ.get("GITHUB_RUN_ID")),
        "measurements": measurements,
    }
    history = history_from_baseline(baseline)
    history.append(snapshot)
    if args.history_limit >= 0:
        history = history[-args.history_limit :] if args.history_limit else []

    report = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": generated_at,
        "generator_revision": snapshot["generator_revision"],
        "github_run_id": snapshot["github_run_id"],
        "measurements": measurements,
        "comparison": {
            "baseline": baseline_description,
            "baseline_error": baseline_error,
            "regression_percent": args.regression_percent,
            "regression_min_ms": args.regression_min_ms,
            "phases": comparisons,
            "regression_count": len(regressions),
        },
        "history": history,
    }
    output = Path(args.output)
    write_json(output, report)

    markdown = markdown_report(
        measurements,
        comparisons,
        baseline_description=baseline_description,
        regression_percent=args.regression_percent,
        regression_min_ms=args.regression_min_ms,
    )
    if args.summary_output is not None:
        summary_path = Path(args.summary_output)
        summary_path.parent.mkdir(parents=True, exist_ok=True)
        with summary_path.open("a", encoding="utf-8") as stream:
            stream.write(markdown)
    print(markdown, end="")
    print(f"[reference-build-metrics] wrote {output}")

    for item in regressions:
        message = (
            f"{item['release_id']}/{item['project_id']} {item['phase']} increased "
            f"from {format_duration(int(item['baseline_ms']))} to "
            f"{format_duration(int(item['current_ms']))} "
            f"({float(item['delta_percent']):+.1f}%)"
        )
        print(f"::warning title=Reference Blueprint timing regression::{message}")
    return 1 if args.fail_on_regression and regressions else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Record and report reference Blueprint build metrics.")
    subparsers = parser.add_subparsers(dest="command_name", required=True)

    record = subparsers.add_parser("record", help="Run one Blueprint generator and record verbose phase timings.")
    record.add_argument("--output", required=True)
    record.add_argument("--project-id", required=True)
    record.add_argument("--release-id", required=True)
    record.add_argument("--source-ref", default="")
    record.add_argument("--toolchain", default="")
    record.add_argument("command", nargs=argparse.REMAINDER)
    record.set_defaults(func=record_build)

    report = subparsers.add_parser("report", help="Aggregate metrics and compare them with a deployed baseline.")
    report.add_argument("--input-root", required=True)
    report.add_argument("--output", required=True)
    baseline = report.add_mutually_exclusive_group()
    baseline.add_argument("--baseline")
    baseline.add_argument("--baseline-url", default=DEFAULT_BASELINE_URL)
    report.add_argument("--summary-output")
    report.add_argument("--regression-percent", type=float, default=DEFAULT_REGRESSION_PERCENT)
    report.add_argument("--regression-min-ms", type=int, default=DEFAULT_REGRESSION_MIN_MS)
    report.add_argument("--history-limit", type=int, default=DEFAULT_HISTORY_LIMIT)
    report.add_argument("--fail-on-regression", action="store_true")
    report.set_defaults(func=report_builds)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

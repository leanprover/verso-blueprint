from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


@dataclass(frozen=True)
class EmbeddedAssetOwner:
    asset: str
    owner: str
    target: str


EMBEDDED_ASSET_OWNERS: tuple[EmbeddedAssetOwner, ...] = (
    EmbeddedAssetOwner("src/VersoBlueprint/blueprint-graph-core.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/blueprint-preview-core.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/blueprint-api-common.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/blueprint-graph-api.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/blueprint-data-api.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/blueprint-preview-api.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/blueprint-page-runtime.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/open-target-details.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/inline-preview.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/graph-runtime-core.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/graph.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Informal/Block/relation-panel.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-base.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-data.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-render.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-source-metadata.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-hydration.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-lifecycle.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-surface.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-template.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-api.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/graph.css", "src/VersoBlueprint/Commands/Graph.lean", "VersoBlueprint.Commands.Graph"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/summary.css", "src/VersoBlueprint/Commands/Summary/Html.lean", "VersoBlueprint.Commands.Summary.Html"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/bibliography.css", "src/VersoBlueprint/Commands/Bibliography.lean", "VersoBlueprint.Commands.Bibliography"),
    EmbeddedAssetOwner("src/VersoBlueprint/Slides/blueprint-slides.css", "src/VersoBlueprint/Slides/Assets.lean", "VersoBlueprint.Slides.Assets"),
    EmbeddedAssetOwner("src/VersoBlueprint/Slides/blueprint-slides.mjs", "src/VersoBlueprint/Slides/Assets.lean", "VersoBlueprint.Slides.Assets"),
    EmbeddedAssetOwner("src/VersoBlueprint/Slides/blueprint-slide-runtime.mjs", "src/VersoBlueprint/Slides/Assets.lean", "VersoBlueprint.Slides.Assets"),
    EmbeddedAssetOwner("static-web/math.js", "src/VersoBlueprint/Macros.lean", "VersoBlueprint.Macros"),
)

INCLUDE_STR_RE = re.compile(r'include_str\s+"([^"]+)"')


@dataclass(frozen=True)
class StepFailure:
    step: str
    detail: str


def format_command(command: list[str]) -> str:
    return " ".join(command)


def run(command: list[str], *, cwd: Path) -> None:
    print(f"[blueprint-harness] $ {format_command(command)}")
    subprocess.run(command, cwd=cwd, check=True)


def format_elapsed(seconds: float) -> str:
    total_seconds = int(seconds)
    minutes, seconds = divmod(total_seconds, 60)
    if minutes:
        return f"{minutes}m{seconds:02d}s"
    return f"{seconds}s"


@contextmanager
def timed_step(label: str):
    start = time.monotonic()
    print(f"[blueprint-harness] starting {label}", flush=True)
    try:
        yield
    except BaseException:
        elapsed = format_elapsed(time.monotonic() - start)
        print(f"[blueprint-harness] failed {label} after {elapsed}", flush=True)
        raise
    else:
        elapsed = format_elapsed(time.monotonic() - start)
        print(f"[blueprint-harness] finished {label} in {elapsed}", flush=True)


def spawn_managed_process(command: list[str], *, cwd: Path) -> subprocess.Popen[bytes]:
    return subprocess.Popen(command, cwd=cwd, start_new_session=os.name == "posix")


def terminate_managed_process(proc: subprocess.Popen[bytes], *, timeout_seconds: int = 5) -> None:
    if proc.poll() is not None:
        return
    if os.name == "posix":
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
    else:
        proc.terminate()
    try:
        proc.wait(timeout=timeout_seconds)
        return
    except subprocess.TimeoutExpired:
        pass
    if os.name == "posix":
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            return
    else:
        proc.kill()
    proc.wait()


def run_with_heartbeat(
    command: list[str],
    *,
    cwd: Path,
    label: str,
    heartbeat_seconds: int = 60,
) -> None:
    print(f"[blueprint-harness] $ {format_command(command)}")
    with timed_step(label):
        start = time.monotonic()
        proc = spawn_managed_process(command, cwd=cwd)
        try:
            while True:
                try:
                    returncode = proc.wait(timeout=heartbeat_seconds)
                    break
                except subprocess.TimeoutExpired:
                    elapsed = format_elapsed(time.monotonic() - start)
                    print(
                        f"[blueprint-harness] still running {label} after {elapsed}: {format_command(command)}",
                        flush=True,
                    )
            if returncode != 0:
                raise subprocess.CalledProcessError(returncode, command)
        except BaseException:
            terminate_managed_process(proc)
            raise


def run_capturing_failure(step: str, command: list[str], *, cwd: Path) -> StepFailure | None:
    try:
        run(command, cwd=cwd)
        return None
    except subprocess.CalledProcessError as err:
        return StepFailure(step=step, detail=f"exit code {err.returncode}: {format_command(command)}")


def print_failure_summary(failures: list[StepFailure], *, prefix: str) -> int:
    if not failures:
        print(f"{prefix} validation summary: all requested steps passed")
        return 0

    print(f"{prefix} validation summary: failures detected", file=sys.stderr)
    for failure in failures:
        print(f"{prefix}   {failure.step}: {failure.detail}", file=sys.stderr)
    return 1


def lean_low_priority_command(package_root: Path, *args: str) -> list[str]:
    return [str(package_root / "scripts" / "lean-low-priority"), *args]


def _source_root_arg(package_root: Path, owner: Path) -> str:
    src_root = package_root / "src"
    try:
        owner.relative_to(src_root)
        return "src"
    except ValueError:
        return "."


def _target_from_source(package_root: Path, source: Path) -> str:
    source_root = package_root / _source_root_arg(package_root, source)
    return ".".join(source.relative_to(source_root).with_suffix("").parts)


def _normalized_relative_path(package_root: Path, path: Path) -> str:
    return path.resolve().relative_to(package_root.resolve()).as_posix()


def discover_embedded_asset_owners(package_root: Path) -> tuple[EmbeddedAssetOwner, ...]:
    discovered: list[EmbeddedAssetOwner] = []
    for owner in sorted((package_root / "src" / "VersoBlueprint").rglob("*.lean")):
        source = owner.read_text(encoding="utf-8")
        owner_rel = _normalized_relative_path(package_root, owner)
        target = _target_from_source(package_root, owner)
        for include_path in INCLUDE_STR_RE.findall(source):
            asset = (owner.parent / include_path).resolve()
            if asset.suffix not in {".css", ".js", ".mjs"}:
                continue
            discovered.append(
                EmbeddedAssetOwner(
                    asset=_normalized_relative_path(package_root, asset),
                    owner=owner_rel,
                    target=target,
                )
            )
    return tuple(discovered)

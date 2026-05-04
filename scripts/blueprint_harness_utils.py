from __future__ import annotations

from dataclasses import dataclass
import os
import subprocess
import sys
from pathlib import Path
import shutil


EMBEDDED_ASSET_OWNER_PATHS: tuple[tuple[str, str, str], ...] = (
    ("src/VersoBlueprint/Commands/graph.css", "src/VersoBlueprint/Commands/Graph.lean", "VersoBlueprint.Commands.Graph"),
    ("src/VersoBlueprint/Commands/graph.js", "src/VersoBlueprint/Commands/Graph.lean", "VersoBlueprint.Commands.Graph"),
    ("src/VersoBlueprint/Commands/summary.css", "src/VersoBlueprint/Commands/Summary.lean", "VersoBlueprint.Commands.Summary"),
    ("src/VersoBlueprint/Commands/bibliography.css", "src/VersoBlueprint/Commands/Bibliography.lean", "VersoBlueprint.Commands.Bibliography"),
    ("static-web/math.js", "src/VersoBlueprint/Macros.lean", "VersoBlueprint.Macros"),
)


@dataclass(frozen=True)
class StepFailure:
    step: str
    detail: str


def format_command(command: list[str]) -> str:
    return " ".join(command)


def run(command: list[str], *, cwd: Path) -> None:
    print(f"[blueprint-harness] $ {format_command(command)}")
    subprocess.run(command, cwd=cwd, check=True)


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


def refresh_embedded_asset_owner_mtimes(package_root: Path) -> list[Path]:
    touched: list[Path] = []
    for asset_rel, owner_rel, _target in EMBEDDED_ASSET_OWNER_PATHS:
        asset = package_root / asset_rel
        owner = package_root / owner_rel
        if not asset.exists() or not owner.exists():
            continue
        if asset.stat().st_mtime_ns <= owner.stat().st_mtime_ns:
            continue
        os.utime(owner, None)
        touched.append(owner)
    return touched


def rebuild_embedded_asset_owners(package_root: Path) -> list[str]:
    touched_targets: list[str] = []
    seen_targets: set[str] = set()
    for asset_rel, owner_rel, target in EMBEDDED_ASSET_OWNER_PATHS:
        asset = package_root / asset_rel
        owner = package_root / owner_rel
        if not asset.exists() or not owner.exists():
            continue
        os.utime(owner, None)
        rel_target_stem = Path(*target.split("."))
        for build_root in (package_root / ".lake" / "build" / "lib" / "lean", package_root / ".lake" / "build" / "ir"):
            base = build_root / rel_target_stem
            for artifact in base.parent.glob(base.name + "*"):
                if artifact.is_dir():
                    shutil.rmtree(artifact)
                else:
                    artifact.unlink()
        if target not in seen_targets:
            touched_targets.append(target)
            seen_targets.add(target)
    if touched_targets:
        run(lean_low_priority_command(package_root, "lake", "build", *touched_targets), cwd=package_root)
    return touched_targets

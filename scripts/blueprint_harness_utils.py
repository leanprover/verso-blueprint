from __future__ import annotations

import os
import subprocess
from pathlib import Path


EMBEDDED_ASSET_OWNER_PATHS: tuple[tuple[str, str, str], ...] = (
    ("src/VersoBlueprint/Commands/graph.css", "src/VersoBlueprint/Commands/Graph.lean", "VersoBlueprint.Commands.Graph"),
    ("src/VersoBlueprint/Commands/graph.js", "src/VersoBlueprint/Commands/Graph.lean", "VersoBlueprint.Commands.Graph"),
    ("src/VersoBlueprint/Commands/summary.css", "src/VersoBlueprint/Commands/Summary.lean", "VersoBlueprint.Commands.Summary"),
    ("src/VersoBlueprint/Commands/bibliography.css", "src/VersoBlueprint/Commands/Bibliography.lean", "VersoBlueprint.Commands.Bibliography"),
    ("static-web/math.js", "src/VersoBlueprint/Macros.lean", "VersoBlueprint.Macros"),
)


def format_command(command: list[str]) -> str:
    return " ".join(command)


def run(command: list[str], *, cwd: Path) -> None:
    print(f"[blueprint-harness] $ {format_command(command)}")
    subprocess.run(command, cwd=cwd, check=True)


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
        if asset.stat().st_mtime_ns <= owner.stat().st_mtime_ns:
            continue
        os.utime(owner, None)
        if target not in seen_targets:
            touched_targets.append(target)
            seen_targets.add(target)
    if touched_targets:
        run(lean_low_priority_command(package_root, "lake", "build", *touched_targets), cwd=package_root)
    return touched_targets

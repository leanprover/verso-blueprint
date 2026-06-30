from __future__ import annotations

from dataclasses import dataclass
import os
import subprocess
import sys
from pathlib import Path
import shutil
import re


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
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-hydration.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-lifecycle.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-surface.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-template.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/preview-runtime-api.mjs", "src/VersoBlueprint/PreviewManifest.lean", "VersoBlueprint.PreviewManifest"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/graph.css", "src/VersoBlueprint/Commands/Graph.lean", "VersoBlueprint.Commands.Graph"),
    EmbeddedAssetOwner("src/VersoBlueprint/Commands/summary.css", "src/VersoBlueprint/Commands/Summary.lean", "VersoBlueprint.Commands.Summary"),
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


def run_output(command: list[str], *, cwd: Path) -> str:
    print(f"[blueprint-harness] $ {format_command(command)}")
    return subprocess.run(command, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE).stdout


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


def _module_build_stem(package_root: Path, build_root: str, target: str) -> Path:
    return package_root / ".lake" / "build" / build_root / Path(*target.split("."))


def _remove_path(path: Path) -> None:
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def _remove_module_artifacts(package_root: Path, target: str) -> None:
    rel_target_stem = Path(*target.split("."))
    for build_root in (package_root / ".lake" / "build" / "lib" / "lean", package_root / ".lake" / "build" / "ir"):
        base = build_root / rel_target_stem
        for artifact in base.parent.glob(base.name + "*"):
            _remove_path(artifact)


def _remove_module_output_sidecars(package_root: Path, target: str) -> None:
    lean_base = _module_build_stem(package_root, "lib/lean", target)
    ir_base = _module_build_stem(package_root, "ir", target)
    for path in (
        lean_base.with_suffix(".olean"),
        lean_base.with_suffix(".olean.hash"),
        lean_base.with_suffix(".ilean"),
        lean_base.with_suffix(".ilean.hash"),
        lean_base.with_suffix(".trace"),
        ir_base.with_suffix(".c"),
        ir_base.with_suffix(".c.hash"),
        ir_base.with_suffix(".setup.json"),
    ):
        _remove_path(path)


def _source_root_arg(package_root: Path, owner: Path) -> str:
    src_root = package_root / "src"
    try:
        owner.relative_to(src_root)
        return "src"
    except ValueError:
        return "."


def _relative_to_package_root(package_root: Path, path: Path) -> str:
    return str(path.relative_to(package_root))


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


def _local_olean_source(package_root: Path, olean: Path) -> Path | None:
    lean_build_root = package_root / ".lake" / "build" / "lib" / "lean"
    try:
        module_rel = olean.relative_to(lean_build_root).with_suffix(".lean")
    except ValueError:
        return None
    source = package_root / "src" / module_rel
    return source if source.exists() else None


def _missing_local_olean_deps(package_root: Path, source: Path) -> list[tuple[Path, str]]:
    command = lean_low_priority_command(
        package_root,
        "lake",
        "env",
        "lean",
        "-Dexperimental.module=true",
        "-R",
        _source_root_arg(package_root, source),
        "--deps",
        _relative_to_package_root(package_root, source),
    )
    deps = []
    seen_targets: set[str] = set()
    for line in run_output(command, cwd=package_root).splitlines():
        dep_olean = Path(line.strip())
        if not dep_olean.name.endswith(".olean") or dep_olean.exists():
            continue
        dep_source = _local_olean_source(package_root, dep_olean)
        if dep_source is None:
            continue
        dep_target = _target_from_source(package_root, dep_source)
        if dep_target in seen_targets:
            continue
        deps.append((dep_source, dep_target))
        seen_targets.add(dep_target)
    return deps


# Lake can satisfy these root-package module targets from the cache by writing a
# synthetic trace without materializing the canonical `.olean`. Generators import
# through the canonical search path, so direct Lean compilation fills that gap.
def _materialize_module_source(
    package_root: Path,
    source: Path,
    target: str,
    materializing: set[str],
) -> bool:
    lean_base = _module_build_stem(package_root, "lib/lean", target)
    ir_base = _module_build_stem(package_root, "ir", target)
    olean = lean_base.with_suffix(".olean")
    if olean.exists():
        return False
    if target in materializing:
        raise RuntimeError(f"cyclic embedded asset owner dependency while materializing {target}")

    materializing.add(target)
    for dep_source, dep_target in _missing_local_olean_deps(package_root, source):
        _materialize_module_source(package_root, dep_source, dep_target, materializing)

    _remove_module_output_sidecars(package_root, target)
    olean.parent.mkdir(parents=True, exist_ok=True)
    ir_base.parent.mkdir(parents=True, exist_ok=True)
    command = lean_low_priority_command(
        package_root,
        "lake",
        "env",
        "lean",
        "-Dexperimental.module=true",
        "-R",
        _source_root_arg(package_root, source),
        "-o",
        _relative_to_package_root(package_root, olean),
        "-i",
        _relative_to_package_root(package_root, lean_base.with_suffix(".ilean")),
        "-c",
        _relative_to_package_root(package_root, ir_base.with_suffix(".c")),
        _relative_to_package_root(package_root, source),
    )
    run(command, cwd=package_root)
    if not olean.exists():
        raise FileNotFoundError(f"expected rebuilt owner module output was not materialized: {olean}")
    materializing.remove(target)
    return True


def _materialize_module_owner(package_root: Path, owner_rel: str, target: str) -> bool:
    return _materialize_module_source(package_root, package_root / owner_rel, target, set())


def ensure_embedded_asset_owner_outputs(package_root: Path) -> list[str]:
    materialized_targets: list[str] = []
    seen_targets: set[str] = set()
    for asset_owner in EMBEDDED_ASSET_OWNERS:
        asset = package_root / asset_owner.asset
        owner = package_root / asset_owner.owner
        if not asset.exists() or not owner.exists() or asset_owner.target in seen_targets:
            continue
        if _materialize_module_owner(package_root, asset_owner.owner, asset_owner.target):
            materialized_targets.append(asset_owner.target)
        seen_targets.add(asset_owner.target)
    return materialized_targets


def refresh_embedded_asset_owner_mtimes(package_root: Path) -> list[Path]:
    touched: list[Path] = []
    for asset_owner in EMBEDDED_ASSET_OWNERS:
        asset = package_root / asset_owner.asset
        owner = package_root / asset_owner.owner
        if not asset.exists() or not owner.exists():
            continue
        if asset.stat().st_mtime_ns <= owner.stat().st_mtime_ns:
            continue
        os.utime(owner, None)
        touched.append(owner)
    return touched


def rebuild_embedded_asset_owners(package_root: Path) -> list[str]:
    touched_targets: list[str] = []
    owners_by_target: dict[str, str] = {}
    seen_targets: set[str] = set()
    for asset_owner in EMBEDDED_ASSET_OWNERS:
        asset = package_root / asset_owner.asset
        owner = package_root / asset_owner.owner
        if not asset.exists() or not owner.exists():
            continue
        os.utime(owner, None)
        _remove_module_artifacts(package_root, asset_owner.target)
        if asset_owner.target not in seen_targets:
            touched_targets.append(asset_owner.target)
            owners_by_target[asset_owner.target] = asset_owner.owner
            seen_targets.add(asset_owner.target)
    if touched_targets:
        run(lean_low_priority_command(package_root, "lake", "build", *touched_targets), cwd=package_root)
        for target in touched_targets:
            _materialize_module_owner(package_root, owners_by_target[target], target)
    return touched_targets

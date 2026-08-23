from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
import json
from pathlib import Path
import re
import shutil

from scripts.blueprint_harness_project_commands import (
    local_blueprint_dependency_override,
    run_project_lake_update,
)
from scripts.blueprint_harness_references import read_reference_toolchain
from scripts.blueprint_harness_utils import lean_low_priority_command, run_with_heartbeat


COMPOSED_PROJECT_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


@dataclass(frozen=True)
class ComposedBlueprint:
    project_id: str
    source_root: Path
    project_dir: Path
    output_dir: Path


def _project_id(value: str) -> str:
    if not COMPOSED_PROJECT_ID_PATTERN.fullmatch(value):
        raise SystemExit(
            "[blueprint-harness] composed Blueprint id must start with an alphanumeric "
            "character and contain only alphanumerics, `.`, `_`, or `-`"
        )
    return value


def resolve_composed_blueprint(
    source_root: Path,
    project_root: str,
    output_root: Path,
    *,
    project_id: str | None,
) -> ComposedBlueprint:
    source_root = source_root.resolve()
    if not source_root.is_dir():
        raise SystemExit(f"[blueprint-harness] composed Blueprint source checkout does not exist: {source_root}")

    relative_project_root = Path(project_root)
    if relative_project_root.is_absolute():
        raise SystemExit("[blueprint-harness] --project-root must be relative to the source checkout")
    project_dir = (source_root / relative_project_root).resolve()
    try:
        project_dir.relative_to(source_root)
    except ValueError as err:
        raise SystemExit("[blueprint-harness] --project-root must stay inside the source checkout") from err
    if not (project_dir / "lakefile.lean").is_file():
        raise SystemExit(f"[blueprint-harness] composed Blueprint project has no lakefile.lean: {project_dir}")

    resolved_id = _project_id(project_id or source_root.name)
    output_dir = output_root.resolve() / resolved_id
    resolved_output_dir = output_dir.resolve()
    if (
        resolved_output_dir == source_root
        or resolved_output_dir in source_root.parents
        or source_root in resolved_output_dir.parents
    ):
        raise SystemExit(
            "[blueprint-harness] composed Blueprint output must not overlap the source checkout: "
            f"output `{output_dir}`, source `{source_root}`"
        )
    return ComposedBlueprint(
        project_id=resolved_id,
        source_root=source_root,
        project_dir=project_dir,
        output_dir=output_dir,
    )


def _nearest_toolchain(project: ComposedBlueprint) -> Path | None:
    for directory in (project.project_dir, *project.project_dir.parents):
        if directory != project.source_root and project.source_root not in directory.parents:
            break
        candidate = directory / "lean-toolchain"
        if candidate.is_file():
            return candidate
        if directory == project.source_root:
            break
    return None


def validate_composed_toolchain(package_root: Path, project: ComposedBlueprint) -> str:
    package_path = package_root / "lean-toolchain"
    project_path = _nearest_toolchain(project)
    package_toolchain = read_reference_toolchain(package_path)
    project_toolchain = read_reference_toolchain(project_path) if project_path is not None else None
    if package_toolchain is None:
        raise SystemExit(f"[blueprint-harness] selected Verso Blueprint checkout has no valid toolchain: {package_path}")
    if project_toolchain is None:
        raise SystemExit(
            "[blueprint-harness] composed Blueprint has no valid lean-toolchain at or above "
            f"{project.project_dir} within {project.source_root}"
        )
    if project_toolchain.lean_ref != package_toolchain.lean_ref:
        raise SystemExit(
            "[blueprint-harness] composed Blueprint toolchain mismatch: "
            f"project `{project.project_dir}` uses Lean `{project_toolchain.lean_ref}`, but "
            f"the selected Verso Blueprint checkout uses `{package_toolchain.lean_ref}`"
        )
    return project_toolchain.lean_ref


def manifest_uses_mathlib(manifest_path: Path) -> bool:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as err:
        raise SystemExit(f"[blueprint-harness] could not inspect composed Lake manifest: {manifest_path}: {err}") from err
    packages = manifest.get("packages")
    if not isinstance(packages, list):
        raise SystemExit(f"[blueprint-harness] composed Lake manifest has no package list: {manifest_path}")
    return any(isinstance(package, dict) and package.get("name") == "mathlib" for package in packages)


def ensure_composed_mathlib_cache(package_root: Path, project_dir: Path) -> bool:
    if not manifest_uses_mathlib(project_dir / "lake-manifest.json"):
        print("[blueprint-harness] composed dependency graph does not include Mathlib")
        return False
    command = lean_low_priority_command(package_root, "lake", "exe", "cache", "get")
    run_with_heartbeat(command, cwd=project_dir, label="composed Blueprint: retrieve Mathlib cache")
    print("[blueprint-harness] composed Blueprint uses the Mathlib cache")
    return True


@contextmanager
def preserve_file(path: Path):
    existed = path.exists()
    original = path.read_bytes() if existed else None
    try:
        yield
    finally:
        if existed and original is not None:
            path.write_bytes(original)
        elif path.exists():
            path.unlink()


def compose_blueprint(package_root: Path, project: ComposedBlueprint, *, verbose: bool = False) -> None:
    validate_composed_toolchain(package_root, project)
    if project.output_dir.exists():
        shutil.rmtree(project.output_dir)
    project.output_dir.mkdir(parents=True, exist_ok=True)

    manifest_path = project.project_dir / "lake-manifest.json"
    with preserve_file(manifest_path):
        with local_blueprint_dependency_override(
            package_root,
            project.project_dir,
            restore_lakefile=True,
            log=True,
        ):
            run_project_lake_update(package_root, project.project_dir)
            ensure_composed_mathlib_cache(package_root, project.project_dir)
            build_command = [
                "lake",
                "exe",
                "vbp",
                "build",
                "--output",
                str(project.output_dir),
            ]
            if verbose:
                build_command.append("--verbose")
            run_with_heartbeat(
                lean_low_priority_command(package_root, *build_command),
                cwd=project.project_dir,
                label=f"{project.project_id}: compose Blueprint",
            )
            run_with_heartbeat(
                lean_low_priority_command(
                    package_root,
                    "lake",
                    "exe",
                    "vbp",
                    "check",
                    "--site",
                    str(project.output_dir),
                ),
                cwd=project.project_dir,
                label=f"{project.project_id}: check composed Blueprint",
            )

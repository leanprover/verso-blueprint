from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from scripts.blueprint_harness_branches import root_checkout_namespace


REFERENCE_PROJECT_RELATIVE_ROOT = Path(".worktrees") / "_reference-blueprints"
REFERENCE_DEPENDENCY_CACHE_RELATIVE_ROOT = REFERENCE_PROJECT_RELATIVE_ROOT / "deps"


@dataclass(frozen=True)
class HarnessLayout:
    package_root: Path
    repo_root: Path
    artifact_root: Path
    worktree_name: str | None

    @property
    def in_linked_worktree(self) -> bool:
        return self.worktree_name is not None

    @property
    def reference_output_root(self) -> Path:
        return self.artifact_root / "reference-blueprints"

    @property
    def test_blueprint_output_root(self) -> Path:
        return self.artifact_root / "test-blueprints"

    @property
    def reference_project_root(self) -> Path:
        return self.repo_root / REFERENCE_PROJECT_RELATIVE_ROOT

    @property
    def reference_source_cache_root(self) -> Path:
        return self.reference_project_root / "cache"

    @property
    def reference_dependency_cache_root(self) -> Path:
        return self.reference_project_root / "deps"

    @property
    def reference_project_checkout_namespace(self) -> str:
        return self.worktree_name or root_checkout_namespace(self.repo_root)

    @property
    def reference_project_checkout_root(self) -> Path:
        return self.reference_project_root / "by-worktree" / self.reference_project_checkout_namespace

    @property
    def reference_project_edit_namespace(self) -> str:
        return self.worktree_name or root_checkout_namespace(self.repo_root)

    @property
    def reference_project_edit_root(self) -> Path:
        return self.reference_project_root / "edit" / self.reference_project_edit_namespace


def find_package_root(start: Path | None = None) -> Path:
    current = (start or Path.cwd()).resolve()
    current_dir = current if current.is_dir() else current.parent
    for candidate in (current_dir, *current_dir.parents):
        if (candidate / "lakefile.lean").exists() and (candidate / "AGENTS.md").exists():
            return candidate
    raise FileNotFoundError(f"Could not locate package root from {current}")


def detect_harness_layout(start: Path | None = None) -> HarnessLayout:
    package_root = find_package_root(start)
    if package_root.parent.name == ".worktrees":
        repo_root = package_root.parents[1]
        worktree_name = package_root.name
        artifact_root = repo_root / "_out" / worktree_name
    else:
        repo_root = package_root
        worktree_name = None
        artifact_root = package_root / "_out"
    return HarnessLayout(
        package_root=package_root,
        repo_root=repo_root,
        artifact_root=artifact_root,
        worktree_name=worktree_name,
    )


def resolve_cli_path(path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path.resolve()
    return (Path.cwd() / path).resolve()


def resolve_output_root(path_text: str | None, start: Path | None = None) -> Path:
    if path_text is not None:
        return resolve_cli_path(path_text)
    return detect_harness_layout(start).reference_output_root


def canonical_reference_project_site_dir(project_id: str, start: Path | None = None) -> Path:
    layout = detect_harness_layout(start)
    return layout.reference_output_root / project_id / "html-multi"


def canonical_test_blueprint_output_dir(name: str, start: Path | None = None) -> Path:
    layout = detect_harness_layout(start)
    return layout.test_blueprint_output_root / name


def canonical_test_blueprint_site_dir(name: str, start: Path | None = None) -> Path:
    return canonical_test_blueprint_output_dir(name, start) / "html-multi"


def default_test_blueprint_site_dir(name: str, start: Path | None = None) -> Path:
    return canonical_test_blueprint_site_dir(name, start)

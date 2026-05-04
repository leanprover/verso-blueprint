from __future__ import annotations

from dataclasses import dataclass, replace
import json
from pathlib import Path

from scripts.blueprint_harness_branches import active_release_branch, normalize_lean_release_ref


# Historical manifest spelling; keep it as the serialized value for existing catalogs.
IN_REPO_PROJECT_SOURCE_KIND = "in_repo_example"
GIT_CHECKOUT_SOURCE_KIND = "git_checkout"


@dataclass(frozen=True)
class HarnessReleaseTarget:
    release_id: str
    toolchain: str
    verso_ref: str
    branch: str
    deploy_pages: bool


@dataclass(frozen=True)
class HarnessProjectTarget:
    release: str
    ref: str | None


@dataclass(frozen=True)
class HarnessProjectCatalog:
    version: int
    release_targets: tuple[HarnessReleaseTarget, ...]
    projects: tuple["HarnessProject", ...]

    def release_target(self, release_id: str) -> HarnessReleaseTarget | None:
        for target in self.release_targets:
            if target.release_id == release_id:
                return target
        return None


@dataclass(frozen=True)
class HarnessProject:
    project_id: str
    source_kind: str
    project_root: str
    build_target: str | None
    generator: str | None
    repository: str | None
    ref: str | None
    build_command: tuple[str, ...] | None
    generate_command: tuple[str, ...] | None
    site_subdir: str
    panel_regression_script: str | None
    browser_tests_path: str | None
    description: str | None
    targets: tuple[HarnessProjectTarget, ...] = ()
    selected_release: str | None = None

    @property
    def in_repo_project(self) -> bool:
        return self.source_kind == IN_REPO_PROJECT_SOURCE_KIND

    @property
    def git_checkout(self) -> bool:
        return self.source_kind == GIT_CHECKOUT_SOURCE_KIND

    @property
    def in_repo_target_project(self) -> bool:
        return self.in_repo_project and self.build_target is not None and self.generator is not None

    @property
    def in_repo_command_project(self) -> bool:
        return self.in_repo_project and self.generate_command is not None

    def target_for_release(self, release: str) -> HarnessProjectTarget | None:
        for target in self.targets:
            if target.release == release:
                return target
        return None


def default_project_manifest(package_root: Path) -> Path:
    return package_root / "tests" / "harness" / "projects.json"


def resolve_manifest_path(path_text: str | None, package_root: Path) -> Path:
    if path_text is None:
        return default_project_manifest(package_root)

    path = Path(path_text)
    if path.is_absolute():
        return path.resolve()
    return (Path.cwd() / path).resolve()


def _require_string(data: dict, key: str, *, context: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f"{context}: expected non-empty string field `{key}`")
    return value


def _optional_string(data: dict, key: str) -> str | None:
    value = data.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise ValueError(f"expected non-empty string field `{key}`")
    return value


def _optional_command(data: dict, key: str, *, context: str) -> tuple[str, ...] | None:
    value = data.get(key)
    if value is None:
        return None
    if not isinstance(value, list) or not value or not all(isinstance(item, str) and item for item in value):
        raise ValueError(f"{context}: expected non-empty string list field `{key}`")
    return tuple(value)


def _optional_bool(data: dict, key: str, *, default: bool, context: str) -> bool:
    value = data.get(key, default)
    if not isinstance(value, bool):
        raise ValueError(f"{context}: expected boolean field `{key}`")
    return value


def _load_release_targets(raw: dict, manifest_path: Path) -> tuple[HarnessReleaseTarget, ...]:
    entries = raw.get("release_targets")
    if not isinstance(entries, list) or not entries:
        raise ValueError(f"{manifest_path}: expected non-empty top-level `release_targets` list")

    targets: list[HarnessReleaseTarget] = []
    seen_ids: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"{manifest_path}: release target #{index} must be an object")
        context = f"{manifest_path}: release target #{index}"
        release_id = normalize_lean_release_ref(_require_string(entry, "id", context=context))
        if release_id in seen_ids:
            raise ValueError(f"{context}: duplicate release target id `{release_id}`")
        seen_ids.add(release_id)
        toolchain = normalize_lean_release_ref(_require_string(entry, "toolchain", context=context))
        verso_ref = normalize_lean_release_ref(_require_string(entry, "verso_ref", context=context))
        branch = normalize_lean_release_ref(_require_string(entry, "branch", context=context))
        deploy_pages = _optional_bool(entry, "deploy_pages", default=False, context=context)
        targets.append(
            HarnessReleaseTarget(
                release_id=release_id,
                toolchain=toolchain,
                verso_ref=verso_ref,
                branch=branch,
                deploy_pages=deploy_pages,
            )
        )
    return tuple(targets)


def _load_project_targets(
    entry: dict,
    *,
    context: str,
    release_ids: set[str],
    source_kind: str,
) -> tuple[HarnessProjectTarget, ...]:
    raw_targets = entry.get("targets")
    if not isinstance(raw_targets, list) or not raw_targets:
        raise ValueError(f"{context}: expected non-empty `targets` list")

    targets: list[HarnessProjectTarget] = []
    seen_releases: set[str] = set()
    for index, raw_target in enumerate(raw_targets, start=1):
        if not isinstance(raw_target, dict):
            raise ValueError(f"{context}: target #{index} must be an object")
        target_context = f"{context}: target #{index}"
        release = normalize_lean_release_ref(_require_string(raw_target, "release", context=target_context))
        if release not in release_ids:
            raise ValueError(f"{target_context}: unknown release target `{release}`")
        if release in seen_releases:
            raise ValueError(f"{target_context}: duplicate release target `{release}`")
        seen_releases.add(release)
        ref = _optional_string(raw_target, "ref")
        if source_kind == GIT_CHECKOUT_SOURCE_KIND and ref is None:
            raise ValueError(f"{target_context}: git checkout targets must declare `ref`")
        if source_kind == IN_REPO_PROJECT_SOURCE_KIND and ref is not None:
            raise ValueError(f"{target_context}: in-repo project targets must not declare `ref`")
        targets.append(
            HarnessProjectTarget(
                release=release,
                ref=ref,
            )
        )
    return tuple(targets)


def load_project_catalog(manifest_path: Path) -> HarnessProjectCatalog:
    raw = json.loads(manifest_path.read_text(encoding="utf-8"))
    if raw.get("version") != 2:
        raise ValueError(f"{manifest_path}: unsupported manifest version {raw.get('version')!r}")
    release_targets = _load_release_targets(raw, manifest_path)
    release_ids = {target.release_id for target in release_targets}

    entries = raw.get("projects")
    if not isinstance(entries, list):
        raise ValueError(f"{manifest_path}: expected top-level `projects` list")

    projects: list[HarnessProject] = []
    seen_ids: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"{manifest_path}: project #{index} must be an object")

        context = f"{manifest_path}: project #{index}"
        project_id = _require_string(entry, "id", context=context)
        if project_id in seen_ids:
            raise ValueError(f"{context}: duplicate project id `{project_id}`")
        seen_ids.add(project_id)

        source = entry.get("source")
        if not isinstance(source, dict):
            raise ValueError(f"{context}: missing object field `source`")
        source_kind = _require_string(source, "kind", context=context)
        project_root = _optional_string(source, "project_root") or "."

        build_target = _optional_string(entry, "build_target")
        generator = _optional_string(entry, "generator")
        repository = _optional_string(source, "repository")
        ref = _optional_string(source, "ref")
        build_command = _optional_command(entry, "build_command", context=context)
        generate_command = _optional_command(entry, "generate_command", context=context)

        validation = entry.get("validation") or {}
        if not isinstance(validation, dict):
            raise ValueError(f"{context}: expected object field `validation`")
        panel_regression_script = _optional_string(validation, "panel_regression_script")
        browser_tests_path = _optional_string(validation, "browser_tests_path")
        description = _optional_string(entry, "description")
        site_subdir = _optional_string(entry, "site_subdir") or "html-multi"
        targets = _load_project_targets(entry, context=context, release_ids=release_ids, source_kind=source_kind)

        if source_kind == IN_REPO_PROJECT_SOURCE_KIND:
            target_mode = build_target is not None or generator is not None
            command_mode = build_command is not None or generate_command is not None
            if target_mode and command_mode:
                raise ValueError(
                    f"{context}: in-repo projects must use either `build_target`/`generator` or "
                    "`build_command`/`generate_command`, not both"
                )
            if target_mode:
                if build_target is None or generator is None:
                    raise ValueError(
                        f"{context}: in-repo projects using root-package targets must declare both "
                        "`build_target` and `generator`"
                    )
                if repository is not None or build_command is not None or generate_command is not None:
                    raise ValueError(
                        f"{context}: in-repo projects using root-package targets must not declare "
                        "`repository`, `build_command`, or `generate_command`"
                    )
            elif command_mode:
                if generate_command is None:
                    raise ValueError(
                        f"{context}: in-repo projects using nested project commands must declare "
                        "`generate_command`"
                    )
                if repository is not None or build_target is not None or generator is not None:
                    raise ValueError(
                        f"{context}: in-repo projects using nested project commands must not declare "
                        "`repository`, `build_target`, or `generator`"
                    )
            else:
                raise ValueError(
                    f"{context}: in-repo projects must declare either `build_target`/`generator` "
                    "or `generate_command`"
                )
        elif source_kind == GIT_CHECKOUT_SOURCE_KIND:
            if repository is None:
                raise ValueError(f"{context}: git checkout projects must declare `source.repository`")
            if generate_command is None:
                raise ValueError(f"{context}: git checkout projects must declare `generate_command`")
            if ref is not None:
                raise ValueError(f"{context}: git checkout projects must declare release-specific refs under `targets`, not `source.ref`")
            if build_target is not None or generator is not None:
                raise ValueError(
                    f"{context}: git checkout projects must not declare `build_target` or `generator`"
                )
        else:
            raise ValueError(f"{context}: unsupported source kind `{source_kind}`")

        projects.append(
            HarnessProject(
                project_id=project_id,
                source_kind=source_kind,
                project_root=project_root,
                build_target=build_target,
                generator=generator,
                repository=repository,
                ref=ref,
                build_command=build_command,
                generate_command=generate_command,
                site_subdir=site_subdir,
                panel_regression_script=panel_regression_script,
                browser_tests_path=browser_tests_path,
                description=description,
                targets=targets,
            )
        )

    return HarnessProjectCatalog(version=2, release_targets=release_targets, projects=tuple(projects))


def load_projects_manifest(manifest_path: Path) -> list[HarnessProject]:
    return list(load_project_catalog(manifest_path).projects)


def resolve_release_target(catalog: HarnessProjectCatalog, release: str | None, package_root: Path) -> HarnessReleaseTarget:
    selected = normalize_lean_release_ref(release) if release is not None else active_release_branch(package_root)
    target = catalog.release_target(selected)
    if target is None:
        known = ", ".join(sorted(entry.release_id for entry in catalog.release_targets))
        raise ValueError(f"{package_root}: unknown release target `{selected}`; known release targets: {known}")
    return target


def resolve_projects_for_release(
    catalog: HarnessProjectCatalog,
    release: str,
    selected_ids: list[str] | None,
) -> list[HarnessProject]:
    by_id = {project.project_id: project for project in catalog.projects}
    if selected_ids is None:
        candidates = list(catalog.projects)
    else:
        seen: set[str] = set()
        candidates: list[HarnessProject] = []
        for value in selected_ids:
            if value not in by_id:
                known = ", ".join(sorted(by_id))
                raise ValueError(f"unknown project `{value}`; known projects: {known}")
            if value not in seen:
                candidates.append(by_id[value])
                seen.add(value)

    resolved: list[HarnessProject] = []
    for project in candidates:
        target = project.target_for_release(release)
        if target is None:
            if selected_ids is not None:
                raise ValueError(f"project `{project.project_id}` has no target for release `{release}`")
            continue
        resolved.append(
            replace(
                project,
                ref=target.ref,
                selected_release=release,
            )
        )
    return resolved


def reference_artifact_name(project: HarnessProject) -> str:
    return f"reference-blueprints-{project.project_id}"


def reference_artifact_path(project: HarnessProject) -> str:
    return f"_out/reference-blueprints/{project.project_id}"


def reference_build_matrix(projects: list[HarnessProject]) -> dict[str, list[dict[str, str]]]:
    return {
        "include": [
            {
                "project_id": project.project_id,
                "artifact_name": reference_artifact_name(project),
                "artifact_path": reference_artifact_path(project),
            }
            for project in projects
        ]
    }


DEPLOY_PROJECT_ARTIFACT_SEPARATOR = "__project__"


def deploy_project_artifact_name(project: HarnessProject) -> str:
    if project.selected_release is None:
        raise ValueError(f"project `{project.project_id}` is missing selected release metadata")
    return (
        f"reference-blueprints-release-{project.selected_release}"
        f"{DEPLOY_PROJECT_ARTIFACT_SEPARATOR}{project.project_id}"
    )


def deploy_project_artifact_path(project: HarnessProject) -> str:
    if project.selected_release is None:
        raise ValueError(f"project `{project.project_id}` is missing selected release metadata")
    return f"_out/reference-blueprints/{project.selected_release}/{project.project_id}"


def deploy_project_matrix(
    release_targets: tuple[HarnessReleaseTarget, ...],
    catalog: HarnessProjectCatalog,
) -> dict[str, list[dict[str, str]]]:
    include: list[dict[str, str]] = []
    for target in release_targets:
        if not target.deploy_pages:
            continue
        for project in resolve_projects_for_release(catalog, target.release_id, None):
            include.append(
                {
                    "release_id": target.release_id,
                    "toolchain": target.toolchain,
                    "verso_ref": target.verso_ref,
                    "branch": target.branch,
                    "project_id": project.project_id,
                    "artifact_name": deploy_project_artifact_name(project),
                    "artifact_path": deploy_project_artifact_path(project),
                }
            )
    return {"include": include}

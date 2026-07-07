from __future__ import annotations

from dataclasses import dataclass, replace
import hashlib
import json
from pathlib import Path
import re

from scripts.blueprint_harness_branches import (
    BranchPolicyReleaseTarget as HarnessReleaseTarget,
    active_release_branch,
    branch_policy_path,
    load_branch_policy,
)
from scripts.blueprint_harness_releases import (
    normalize_lean_release_ref,
    normalize_release_candidate_name,
    release_candidate_ref,
    release_branch_from_lean_ref,
)
from scripts.blueprint_harness_manifest import (
    load_json_object,
    optional_bool as _optional_bool,
    optional_command as _optional_command,
    optional_string as _optional_string,
    require_string as _require_string,
    resolve_manifest_path as resolve_manifest_file_path,
)


IN_REPO_PROJECT_SOURCE_KIND = "in_repo_project"
GIT_CHECKOUT_SOURCE_KIND = "git_checkout"
REFERENCE_CACHE_KEY_DIGEST_LENGTH = 12


@dataclass(frozen=True)
class HarnessProjectTarget:
    release: str
    ref: str | None
    publish_reference: bool = False
    rc: str | None = None


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
    selected_rc: str | None = None

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


def _reference_cache_key_slug(value: str, *, max_length: int) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip(".-_")
    return (slug or "unknown")[:max_length].strip(".-_") or "unknown"


def _short_reference_cache_ref(ref: str) -> str:
    if len(ref) == 40 and all(char in "0123456789abcdefABCDEF" for char in ref):
        return ref[:12]
    return ref


def reference_dependency_cache_key(project: HarnessProject) -> str:
    """Key dependency cache state for one external project source ref.

    The key intentionally ignores the selected release and local package root:
    the expensive state being reused is the external project's pinned Lake
    dependency packages, not the generated Blueprint site or local checkout
    build output.
    """
    if not project.git_checkout:
        raise ValueError(f"project `{project.project_id}` is not an external git checkout project")
    if project.repository is None:
        raise ValueError(f"project `{project.project_id}` is missing repository metadata")
    if project.ref is None:
        raise ValueError(f"project `{project.project_id}` is missing selected git ref metadata")

    key_material = json.dumps(
        {
            "repository": project.repository,
            "project_root": project.project_root,
            "ref": project.ref,
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    digest = hashlib.sha256(key_material.encode("utf-8")).hexdigest()[:REFERENCE_CACHE_KEY_DIGEST_LENGTH]
    project_slug = _reference_cache_key_slug(project.project_id, max_length=48)
    ref_slug = _reference_cache_key_slug(_short_reference_cache_ref(project.ref), max_length=40)
    return f"{project_slug}-{ref_slug}-{digest}"


def default_project_manifest(package_root: Path) -> Path:
    return package_root / "tests" / "harness" / "projects.json"


def resolve_manifest_path(path_text: str | None, package_root: Path) -> Path:
    return resolve_manifest_file_path(path_text, default_project_manifest(package_root))


def _package_root_for_manifest(manifest_path: Path | str) -> Path | None:
    path = Path(manifest_path)
    candidates = path.parents if path.suffix else (path, *path.parents)
    for parent in candidates:
        if branch_policy_path(parent).exists():
            return parent
    return None


def _load_release_targets(raw: dict, manifest_path: Path | str) -> tuple[HarnessReleaseTarget, ...]:
    entries = raw.get("release_targets")
    if entries is None:
        package_root = _package_root_for_manifest(manifest_path)
        if package_root is None:
            raise ValueError(
                f"{manifest_path}: expected top-level `release_targets` list or nearby `branch-policy.json`"
            )
        targets = load_branch_policy(package_root).release_targets
        if not targets:
            raise ValueError(f"{branch_policy_path(package_root)}: expected non-empty `release_targets` list")
        return targets
    if not isinstance(entries, list) or not entries:
        raise ValueError(f"{manifest_path}: expected non-empty top-level `release_targets` list")

    targets: list[HarnessReleaseTarget] = []
    seen_ids: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"{manifest_path}: release target #{index} must be an object")
        context = f"{manifest_path}: release target #{index}"
        release_id = release_branch_from_lean_ref(_require_string(entry, "id", context=context))
        if release_id in seen_ids:
            raise ValueError(f"{context}: duplicate release target id `{release_id}`")
        seen_ids.add(release_id)
        toolchain = normalize_lean_release_ref(_require_string(entry, "toolchain", context=context))
        verso_ref = normalize_lean_release_ref(_require_string(entry, "verso_ref", context=context))
        branch = release_branch_from_lean_ref(_require_string(entry, "branch", context=context))
        deploy_pages = _optional_bool(entry, "deploy_pages", default=False, context=context)
        rc = entry.get("rc")
        if rc is not None:
            raise ValueError(f"{context}: `rc` belongs on project targets, not release targets")
        targets.append(
            HarnessReleaseTarget(
                release_id=release_id,
                release_toolchain=toolchain,
                release_verso_ref=verso_ref,
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
        release = release_branch_from_lean_ref(_require_string(raw_target, "release", context=target_context))
        if release not in release_ids:
            raise ValueError(f"{target_context}: unknown release target `{release}`")
        if release in seen_releases:
            raise ValueError(f"{target_context}: duplicate release target `{release}`")
        seen_releases.add(release)
        ref = _optional_string(raw_target, "ref", context=target_context)
        if source_kind == GIT_CHECKOUT_SOURCE_KIND and ref is None:
            raise ValueError(f"{target_context}: git checkout targets must declare `ref`")
        if source_kind == IN_REPO_PROJECT_SOURCE_KIND and ref is not None:
            raise ValueError(f"{target_context}: in-repo project targets must not declare `ref`")
        if "publish" in raw_target:
            raise ValueError(f"{target_context}: `publish` is no longer supported; use `publish_reference`")
        rc = raw_target.get("rc")
        if rc is not None:
            if not isinstance(rc, str):
                raise ValueError(f"{target_context}: expected string field `rc`")
            rc = normalize_release_candidate_name(rc)
            if release_branch_from_lean_ref(rc) != release:
                raise ValueError(f"{target_context}: `rc` `{rc}` does not belong to release `{release}`")
        targets.append(
            HarnessProjectTarget(
                release=release,
                ref=ref,
                publish_reference=_optional_bool(raw_target, "publish_reference", default=False, context=target_context),
                rc=rc,
            )
        )
    return tuple(targets)


def load_project_catalog_data(raw: dict, manifest_path: Path | str) -> HarnessProjectCatalog:
    if raw.get("version") != 2:
        raise ValueError(f"{manifest_path}: unsupported manifest version {raw.get('version')!r}")
    if "reference_blueprints" in raw:
        raise ValueError(
            f"{manifest_path}: top-level `reference_blueprints` is no longer supported; "
            "mark published project targets with `publish_reference`"
        )
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
        project_root = _optional_string(source, "project_root", context=context) or "."

        build_target = _optional_string(entry, "build_target", context=context)
        generator = _optional_string(entry, "generator", context=context)
        repository = _optional_string(source, "repository", context=context)
        ref = _optional_string(source, "ref", context=context)
        build_command = _optional_command(entry, "build_command", context=context)
        generate_command = _optional_command(entry, "generate_command", context=context)

        validation = entry.get("validation") or {}
        if not isinstance(validation, dict):
            raise ValueError(f"{context}: expected object field `validation`")
        panel_regression_script = _optional_string(validation, "panel_regression_script", context=context)
        browser_tests_path = _optional_string(validation, "browser_tests_path", context=context)
        description = _optional_string(entry, "description", context=context)
        site_subdir = _optional_string(entry, "site_subdir", context=context) or "html-multi"
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

    return HarnessProjectCatalog(
        version=2,
        release_targets=release_targets,
        projects=tuple(projects),
    )


def load_project_catalog(manifest_path: Path) -> HarnessProjectCatalog:
    raw = load_json_object(manifest_path)
    return load_project_catalog_data(raw, manifest_path)


def resolve_release_target(catalog: HarnessProjectCatalog, release: str | None, package_root: Path) -> HarnessReleaseTarget:
    selected = release_branch_from_lean_ref(release) if release is not None else active_release_branch(package_root)
    target = catalog.release_target(selected)
    if target is None:
        known = ", ".join(sorted(entry.release_id for entry in catalog.release_targets))
        raise ValueError(f"{package_root}: unknown release target `{selected}`; known release targets: {known}")
    return target


def resolve_projects_for_release(
    catalog: HarnessProjectCatalog,
    release: str,
    selected_ids: list[str] | None,
    *,
    require_selected_targets: bool = True,
) -> list[HarnessProject]:
    by_id = {project.project_id: project for project in catalog.projects}

    if selected_ids is None:
        candidates = [
            project
            for project in catalog.projects
            if (target := project.target_for_release(release)) is not None and target.publish_reference
        ]
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
            if selected_ids is not None and require_selected_targets:
                raise ValueError(f"project `{project.project_id}` has no target for release `{release}`")
            continue
        resolved.append(
            replace(
                project,
                ref=target.ref,
                selected_release=release,
                selected_rc=target.rc,
            )
        )
    return resolved


def resolve_release_projects(
    catalog: HarnessProjectCatalog,
    release: str | None,
    package_root: Path,
    selected_ids: list[str] | None,
    *,
    require_selected_targets: bool = True,
) -> tuple[HarnessReleaseTarget, list[HarnessProject]]:
    release_target = resolve_release_target(catalog, release, package_root)
    projects = resolve_projects_for_release(
        catalog,
        release_target.release_id,
        selected_ids,
        require_selected_targets=require_selected_targets,
    )
    return release_target, projects


def reference_artifact_name(project: HarnessProject) -> str:
    return f"reference-blueprints-{project.project_id}"


def reference_artifact_path(project: HarnessProject) -> str:
    return f"_out/reference-blueprints/{project.project_id}"


def project_target_rc(project: HarnessProject) -> str:
    return project.selected_rc or ""


def project_target_toolchain(release_target: HarnessReleaseTarget, project: HarnessProject) -> str:
    return release_candidate_ref(project.selected_rc) if project.selected_rc is not None else release_target.toolchain


def project_target_verso_ref(release_target: HarnessReleaseTarget, project: HarnessProject) -> str:
    return release_candidate_ref(project.selected_rc) if project.selected_rc is not None else release_target.verso_ref


def reference_project_target_fields(
    project: HarnessProject,
    release_target: HarnessReleaseTarget,
) -> dict[str, object]:
    return {
        "project_id": project.project_id,
        "rc": project_target_rc(project),
        "toolchain": project_target_toolchain(release_target, project),
        "verso_ref": project_target_verso_ref(release_target, project),
        "project_root": project.project_root,
        "hash": project.ref,
        "reference_cache_key": reference_dependency_cache_key(project) if project.git_checkout else "",
    }


def reference_build_matrix(
    projects: list[HarnessProject],
    release_target: HarnessReleaseTarget,
) -> dict[str, list[dict[str, object]]]:
    include: list[dict[str, object]] = []
    for project in projects:
        entry = reference_project_target_fields(project, release_target)
        entry.update(
            {
                "artifact_name": reference_artifact_name(project),
                "artifact_path": reference_artifact_path(project),
            }
        )
        include.append(entry)
    return {"include": include}


def reference_release_payload(
    manifest_path: Path,
    catalog: HarnessProjectCatalog,
    release: str | None,
    package_root: Path,
) -> dict[str, object]:
    release_target = resolve_release_target(catalog, release, package_root)
    projects = resolve_projects_for_release(catalog, release_target.release_id, None)
    return {
        "manifest_path": str(manifest_path),
        "release_id": release_target.release_id,
        "rc": "",
        "toolchain": release_target.toolchain,
        "verso_ref": release_target.verso_ref,
        "branch": release_target.branch,
        "deploy_pages": release_target.deploy_pages,
        "reference_project_count": len(projects),
        "reference_matrix": reference_build_matrix(projects, release_target),
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


def release_target_manifest_entry(target: HarnessReleaseTarget) -> dict[str, object]:
    return {
        "id": target.release_id,
        "toolchain": target.release_toolchain,
        "verso_ref": target.release_verso_ref,
        "branch": target.branch,
        "deploy_pages": target.deploy_pages,
    }


def command_with_pdf(command: tuple[str, ...]) -> tuple[str, ...]:
    if "--pdf" in command:
        return command
    return (*command, "--pdf")


def project_manifest_entry(project: HarnessProject, *, include_pdf: bool = False) -> dict[str, object]:
    if project.selected_release is None:
        raise ValueError(f"project `{project.project_id}` is missing selected release metadata")

    source: dict[str, object] = {
        "kind": project.source_kind,
        "project_root": project.project_root,
    }
    if project.repository is not None:
        source["repository"] = project.repository

    target: dict[str, object] = {"release": project.selected_release}
    if project.ref is not None:
        target["ref"] = project.ref
    if project.selected_rc is not None:
        target["rc"] = project.selected_rc

    entry: dict[str, object] = {
        "id": project.project_id,
        "source": source,
        "targets": [target],
        "site_subdir": project.site_subdir,
    }
    if project.description is not None:
        entry["description"] = project.description
    if project.build_target is not None:
        entry["build_target"] = project.build_target
    if project.generator is not None:
        entry["generator"] = project.generator
    if project.build_command is not None:
        entry["build_command"] = list(project.build_command)
    if project.generate_command is not None:
        generate_command = project.generate_command
        if include_pdf:
            generate_command = command_with_pdf(generate_command)
        entry["generate_command"] = list(generate_command)
    elif include_pdf:
        raise ValueError(f"project `{project.project_id}` needs a `generate_command` to publish PDF output")
    validation: dict[str, object] = {}
    if project.panel_regression_script is not None:
        validation["panel_regression_script"] = project.panel_regression_script
    if project.browser_tests_path is not None:
        validation["browser_tests_path"] = project.browser_tests_path
    if validation:
        entry["validation"] = validation
    return entry


def deploy_project_manifest(
    target: HarnessReleaseTarget,
    project: HarnessProject,
    *,
    include_pdf: bool = True,
) -> dict[str, object]:
    return {
        "version": 2,
        "release_targets": [release_target_manifest_entry(target)],
        "projects": [project_manifest_entry(project, include_pdf=include_pdf)],
    }


def deploy_matrix_from_controller_catalog(
    controller_catalog: HarnessProjectCatalog,
    deployable_targets: tuple[HarnessReleaseTarget, ...],
) -> dict[str, list[dict[str, object]]]:
    include: list[dict[str, object]] = []
    for target in deployable_targets:
        controller_projects = resolve_projects_for_release(controller_catalog, target.release_id, None)
        if not controller_projects:
            raise ValueError(
                f"release target `{target.release_id}` has `deploy_pages: true` but no published "
                "reference project targets"
            )
        for project in controller_projects:
            fields = reference_project_target_fields(project, target)
            include.append(
                {
                    "release_id": target.release_id,
                    "rc": fields["rc"],
                    "toolchain": fields["toolchain"],
                    "verso_ref": fields["verso_ref"],
                    "branch": target.branch,
                    "project_id": fields["project_id"],
                    "project_root": fields["project_root"],
                    "hash": fields["hash"],
                    "reference_cache_key": fields["reference_cache_key"],
                    "artifact_name": deploy_project_artifact_name(project),
                    "artifact_path": deploy_project_artifact_path(project),
                    "project_manifest": deploy_project_manifest(target, project),
                }
            )
    return {"include": include}

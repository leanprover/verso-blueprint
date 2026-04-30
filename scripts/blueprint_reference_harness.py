from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys

from scripts.blueprint_harness_branches import active_release_branch, local_release_ref, root_checkout_namespace
from scripts.blueprint_harness import current_branch_name, main_sync_status, ref_oid, ref_sync_status, worktree_is_clean
from scripts.blueprint_harness_cli import (
    add_allow_local_build_argument,
    add_allow_unsafe_root_main_argument,
    add_manifest_argument,
    add_output_root_argument,
    add_project_selection_argument,
    add_serial_argument,
)
from scripts.blueprint_harness_paths import detect_harness_layout, resolve_output_root
from scripts.blueprint_harness_projects import HarnessProject, resolve_manifest_path
from scripts.blueprint_harness_projects import (
    HarnessProjectCatalog,
    load_project_catalog as load_project_catalog_manifest,
    resolve_projects_for_release,
    resolve_release_target,
)
from scripts.blueprint_harness_references import (
    bump_reference_project,
    OFFICIAL_BLUEPRINT_URL_PATTERNS,
    clone_git_project,
    generate_in_repo_command_project,
    generate_git_project,
    output_dir_for,
    prepare_reference_edit_checkout,
    ref_is_commit_hash,
    reference_cache_checkout_dir,
    reference_prune_plan,
    site_dir_for,
    sync_reference_blueprints,
)
from scripts.blueprint_harness_utils import format_command, lean_low_priority_command, run
from scripts.blueprint_harness_worktrees import git_worktrees, rev_list_counts


@dataclass(frozen=True)
class StepFailure:
    step: str
    detail: str


@dataclass(frozen=True)
class BlueprintDependencyPin:
    source_path: str
    input_ref: str | None
    resolved_ref: str | None


@dataclass(frozen=True)
class ReferenceProjectStatus:
    project: HarnessProject
    catalog_ref: str | None
    project_upstream_ref: str | None
    project_relationship: str | None
    project_ahead: int | None
    project_behind: int | None
    blueprint_pin: BlueprintDependencyPin | None
    blueprint_relationship: str | None
    blueprint_ahead: int | None
    blueprint_behind: int | None
    skipped: str | None = None
    error: str | None = None


@dataclass(frozen=True)
class ReleaseTargetStatus:
    release_id: str
    toolchain: str
    verso_ref: str
    branch: str
    deploy_pages: bool
    project_statuses: tuple[ReferenceProjectStatus, ...]


BLUEPRINT_REQUIRE_PATTERN = re.compile(
    r'require\s+VersoBlueprint\s+from\s+git\s+"(?P<url>[^"]+)"(?:\s*@\s*"(?P<ref>[^"]+)")?',
    re.MULTILINE | re.DOTALL,
)


def run_capturing_failure(step: str, command: list[str], *, cwd: Path) -> StepFailure | None:
    try:
        run(command, cwd=cwd)
        return None
    except subprocess.CalledProcessError as err:
        return StepFailure(step=step, detail=f"exit code {err.returncode}: {format_command(command)}")


def text_or_blank(value: object | None) -> str:
    return "" if value is None else str(value)


def official_blueprint_source(url: str) -> bool:
    return any(re.fullmatch(pattern, url) for pattern in OFFICIAL_BLUEPRINT_URL_PATTERNS)


def project_git_path(project: HarnessProject, filename: str) -> str:
    if project.project_root in {"", "."}:
        return filename
    return str(PurePosixPath(project.project_root) / filename)


def git_show_text(checkout_root: Path, ref: str, path: str) -> str | None:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path}"],
        cwd=checkout_root,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def parse_blueprint_manifest_pin(text: str, *, source_path: str) -> BlueprintDependencyPin | None:
    data = json.loads(text)
    packages = data.get("packages")
    if not isinstance(packages, list):
        return None

    for package in packages:
        if not isinstance(package, dict) or package.get("name") != "VersoBlueprint":
            continue
        if package.get("type") != "git":
            continue
        url = package.get("url")
        if not isinstance(url, str) or not official_blueprint_source(url):
            continue
        input_ref = package.get("inputRev")
        resolved_ref = package.get("rev")
        return BlueprintDependencyPin(
            source_path=source_path,
            input_ref=input_ref if isinstance(input_ref, str) else None,
            resolved_ref=resolved_ref if isinstance(resolved_ref, str) else None,
        )
    return None


def parse_blueprint_lakefile_pin(text: str, *, source_path: str) -> BlueprintDependencyPin | None:
    for match in BLUEPRINT_REQUIRE_PATTERN.finditer(text):
        url = match.group("url")
        if not official_blueprint_source(url):
            continue
        return BlueprintDependencyPin(
            source_path=source_path,
            input_ref=match.group("ref"),
            resolved_ref=match.group("ref"),
        )
    return None


def blueprint_pin_at_project_ref(checkout_root: Path, project: HarnessProject, project_ref: str) -> BlueprintDependencyPin | None:
    manifest_path = project_git_path(project, "lake-manifest.json")
    manifest_text = git_show_text(checkout_root, project_ref, manifest_path)
    if manifest_text is not None:
        pin = parse_blueprint_manifest_pin(manifest_text, source_path=manifest_path)
        if pin is not None:
            return pin

    lakefile_path = project_git_path(project, "lakefile.lean")
    lakefile_text = git_show_text(checkout_root, project_ref, lakefile_path)
    if lakefile_text is None:
        return None
    return parse_blueprint_lakefile_pin(lakefile_text, source_path=lakefile_path)


def git_is_shallow(checkout_root: Path) -> bool:
    result = subprocess.run(
        ["git", "rev-parse", "--is-shallow-repository"],
        cwd=checkout_root,
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout.strip() == "true"


def refresh_reference_status_checkout(checkout_root: Path, project: HarnessProject) -> None:
    if git_is_shallow(checkout_root):
        subprocess.run(
            ["git", "fetch", "--quiet", "--unshallow", "origin"],
            cwd=checkout_root,
            check=True,
            text=True,
            capture_output=True,
        )
    else:
        subprocess.run(
            ["git", "fetch", "--quiet", "--prune", "origin"],
            cwd=checkout_root,
            check=True,
            text=True,
            capture_output=True,
        )
    if project.ref is not None and ref_is_commit_hash(project.ref):
        subprocess.run(
            ["git", "fetch", "--quiet", "origin", project.ref],
            cwd=checkout_root,
            check=True,
            text=True,
            capture_output=True,
        )


def ensure_reference_status_checkout(layout, project: HarnessProject) -> Path:
    checkout_root = reference_cache_checkout_dir(layout, project)
    checkout_root.parent.mkdir(parents=True, exist_ok=True)
    if not checkout_root.exists():
        clone_git_project(project, checkout_root, cwd=layout.package_root, shallow=False)
    refresh_reference_status_checkout(checkout_root, project)
    return checkout_root


def reference_project_upstream_ref(checkout_root: Path) -> str | None:
    result = subprocess.run(
        ["git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
        cwd=checkout_root,
        check=False,
        text=True,
        capture_output=True,
    )
    upstream = result.stdout.strip()
    if upstream:
        return upstream
    for candidate in ("origin/main", "origin/master"):
        if ref_oid(checkout_root, candidate) is not None:
            return candidate
    return None


def project_catalog_ref(checkout_root: Path, project: HarnessProject) -> str | None:
    ref = project.ref or reference_project_upstream_ref(checkout_root)
    if ref is None:
        return None
    if ref.startswith("origin/"):
        remote_ref = ref
        if ref_oid(checkout_root, remote_ref) is not None:
            return remote_ref
        ref = ref[len("origin/") :]
    if ref_is_commit_hash(ref):
        return ref
    remote_ref = f"origin/{ref}"
    if ref_oid(checkout_root, remote_ref) is not None:
        return remote_ref
    if ref_oid(checkout_root, ref) is not None:
        return ref
    return None


def compare_refs(repo_root: Path, ref: str | None, base_ref: str | None) -> tuple[str | None, int | None, int | None]:
    if ref is None or base_ref is None:
        return None, None, None
    status = ref_sync_status(repo_root, ref, base_ref)
    ahead, behind = rev_list_counts(repo_root, ref, base_ref)
    return status.relationship, ahead, behind


def local_compare_ref(repo_root: Path, ref: str | None) -> str | None:
    if ref is None:
        return None
    local_ref = f"refs/heads/{ref}"
    if ref_oid(repo_root, local_ref) is not None:
        return local_ref
    return ref


def collect_reference_project_status(layout, project: HarnessProject, *, blueprint_base_ref: str | None = None) -> ReferenceProjectStatus:
    if not project.git_checkout:
        return ReferenceProjectStatus(
            project=project,
            catalog_ref=None,
            project_upstream_ref=None,
            project_relationship=None,
            project_ahead=None,
            project_behind=None,
            blueprint_pin=None,
            blueprint_relationship=None,
            blueprint_ahead=None,
            blueprint_behind=None,
            skipped="in_repo_example",
        )

    checkout_root = ensure_reference_status_checkout(layout, project)
    upstream_ref = reference_project_upstream_ref(checkout_root)
    catalog_ref = project_catalog_ref(checkout_root, project)
    project_relationship, project_ahead, project_behind = compare_refs(checkout_root, catalog_ref, upstream_ref)
    blueprint_pin = blueprint_pin_at_project_ref(checkout_root, project, catalog_ref) if catalog_ref is not None else None
    blueprint_ref = None
    if blueprint_pin is not None:
        blueprint_ref = blueprint_pin.resolved_ref or blueprint_pin.input_ref
    blueprint_relationship, blueprint_ahead, blueprint_behind = compare_refs(
        layout.repo_root,
        blueprint_ref,
        local_compare_ref(layout.repo_root, blueprint_base_ref or local_release_ref(layout.repo_root)),
    )

    return ReferenceProjectStatus(
        project=project,
        catalog_ref=catalog_ref,
        project_upstream_ref=upstream_ref,
        project_relationship=project_relationship,
        project_ahead=project_ahead,
        project_behind=project_behind,
        blueprint_pin=blueprint_pin,
        blueprint_relationship=blueprint_relationship,
        blueprint_ahead=blueprint_ahead,
        blueprint_behind=blueprint_behind,
    )


def print_reference_project_status(status: ReferenceProjectStatus) -> None:
    project = status.project
    source = f"in_repo:{project.project_root}" if project.in_repo_example else f"git:{project.repository}@{project.ref}"
    fields = [
        project.project_id,
        f"source={source}",
        f"catalog_ref={text_or_blank(status.catalog_ref)}",
        f"project_upstream_ref={text_or_blank(status.project_upstream_ref)}",
        f"catalog_status={text_or_blank(status.project_relationship)}",
        f"catalog_ahead={text_or_blank(status.project_ahead)}",
        f"catalog_behind={text_or_blank(status.project_behind)}",
        f"blueprint_pin_source={text_or_blank(status.blueprint_pin.source_path if status.blueprint_pin is not None else None)}",
        f"blueprint_input_ref={text_or_blank(status.blueprint_pin.input_ref if status.blueprint_pin is not None else None)}",
        f"blueprint_resolved_ref={text_or_blank(status.blueprint_pin.resolved_ref if status.blueprint_pin is not None else None)}",
        f"blueprint_status={text_or_blank(status.blueprint_relationship)}",
        f"blueprint_ahead={text_or_blank(status.blueprint_ahead)}",
        f"blueprint_behind={text_or_blank(status.blueprint_behind)}",
        f"skip={text_or_blank(status.skipped)}",
        f"error={text_or_blank(status.error)}",
    ]
    print("\t".join(fields))


def project_target_is_outdated(status: ReferenceProjectStatus) -> bool:
    if status.error is not None:
        return True
    if not status.project.git_checkout:
        return False
    return status.project_relationship in {"behind", "diverged", "missing_local", "missing_upstream"}


def downstream_blueprint_pin_has_drift(status: ReferenceProjectStatus) -> bool:
    if status.error is not None:
        return False
    return status.blueprint_relationship in {"behind", "diverged", "missing_local", "missing_upstream"}


def status_has_catalog_issue(status: ReferenceProjectStatus) -> bool:
    return project_target_is_outdated(status)


def print_release_target_summary(status: ReleaseTargetStatus) -> None:
    outdated_projects = sum(1 for project_status in status.project_statuses if project_target_is_outdated(project_status))
    downstream_pin_drift = sum(1 for project_status in status.project_statuses if downstream_blueprint_pin_has_drift(project_status))
    print(
        "\t".join(
            [
                f"release={status.release_id}",
                f"toolchain={status.toolchain}",
                f"verso_ref={status.verso_ref}",
                f"branch={status.branch}",
                f"deploy_pages={str(status.deploy_pages).lower()}",
                f"project_count={len(status.project_statuses)}",
                f"outdated_projects={outdated_projects}",
                f"downstream_pin_drift={downstream_pin_drift}",
            ]
        )
    )


def print_release_target_project_status(release_id: str, status: ReferenceProjectStatus) -> None:
    project = status.project
    source = f"in_repo:{project.project_root}" if project.in_repo_example else f"git:{project.repository}@{project.ref}"
    fields = [
        f"release={release_id}",
        f"project={project.project_id}",
        f"source={source}",
        f"catalog_ref={text_or_blank(status.catalog_ref)}",
        f"project_upstream_ref={text_or_blank(status.project_upstream_ref)}",
        f"catalog_status={text_or_blank(status.project_relationship)}",
        f"catalog_ahead={text_or_blank(status.project_ahead)}",
        f"catalog_behind={text_or_blank(status.project_behind)}",
        f"outdated={str(project_target_is_outdated(status)).lower()}",
        f"blueprint_pin_source={text_or_blank(status.blueprint_pin.source_path if status.blueprint_pin is not None else None)}",
        f"blueprint_resolved_ref={text_or_blank(status.blueprint_pin.resolved_ref if status.blueprint_pin is not None else None)}",
        f"blueprint_status={text_or_blank(status.blueprint_relationship)}",
        f"downstream_pin_drift={str(downstream_blueprint_pin_has_drift(status)).lower()}",
        f"skip={text_or_blank(status.skipped)}",
        f"error={text_or_blank(status.error)}",
    ]
    print("\t".join(fields))


def load_project_catalog(manifest_path: Path) -> HarnessProjectCatalog:
    try:
        return load_project_catalog_manifest(manifest_path)
    except (FileNotFoundError, ValueError) as err:
        raise SystemExit(f"[blueprint-reference-harness] {err}") from err


def select_release_projects(
    catalog: HarnessProjectCatalog,
    *,
    release: str | None,
    project_ids: list[str] | None,
    package_root: Path,
) -> tuple[str, list[HarnessProject]]:
    try:
        selected_release = resolve_release_target(catalog, release, package_root)
        projects = resolve_projects_for_release(catalog, selected_release.release_id, project_ids)
    except ValueError as err:
        raise SystemExit(f"[blueprint-reference-harness] {err}") from err
    return selected_release.release_id, projects


def require_checkout_release(layout, release_id: str, *, command_name: str) -> None:
    active_release = active_release_branch(layout.package_root)
    if release_id == active_release:
        return
    raise SystemExit(
        f"[blueprint-reference-harness] refusing to run `{command_name}` for release target `{release_id}` "
        f"from checkout release `{active_release}`. Create or switch to a `{release_id}` checkout first."
    )


def selected_release_targets(catalog: HarnessProjectCatalog, release: str | None, package_root: Path) -> tuple[object, ...]:
    if release is not None:
        try:
            return (resolve_release_target(catalog, release, package_root),)
        except ValueError as err:
            raise SystemExit(f"[blueprint-reference-harness] {err}") from err
    return catalog.release_targets


def should_use_local_build(layout, allow_local_build: bool) -> bool:
    return (not layout.in_linked_worktree) or allow_local_build


def root_main_safety_findings(layout) -> list[str]:
    if layout.in_linked_worktree:
        return []
    release_branch = active_release_branch(layout.repo_root)
    if current_branch_name(layout.repo_root) != release_branch:
        return []

    findings: list[str] = []
    if not worktree_is_clean(layout.package_root):
        findings.append("root checkout has local modifications")
    status = main_sync_status(layout.repo_root)
    if status.relationship != "in_sync":
        findings.append(f"local `{release_branch}` is {status.relationship} relative to `{status.upstream_ref}`")
    return findings


def require_safe_root_main(layout, *, allow_unsafe: bool, command_name: str) -> None:
    findings = root_main_safety_findings(layout)
    if not findings:
        return

    details = "; ".join(findings)
    if allow_unsafe:
        print(
            f"[blueprint-reference-harness] warning: running `{command_name}` from an unsafe root checkout: {details}",
            file=sys.stderr,
        )
        return

    raise SystemExit(
        f"[blueprint-reference-harness] refusing to run `{command_name}` from the root checkout: {details}. "
        "Create a linked worktree or pass `--allow-unsafe-root-release` to override."
    )


def print_failure_summary(failures: list[StepFailure]) -> int:
    if not failures:
        print("[blueprint-reference-harness] validation summary: all requested steps passed")
        return 0

    print("[blueprint-reference-harness] validation summary: failures detected", file=sys.stderr)
    for failure in failures:
        print(f"[blueprint-reference-harness]   {failure.step}: {failure.detail}", file=sys.stderr)
    return 1


def executable_path(package_root: Path, exe_name: str) -> Path:
    return package_root / ".lake" / "build" / "bin" / exe_name


def ensure_prebuilt_executable(package_root: Path, exe_name: str) -> Path:
    path = executable_path(package_root, exe_name)
    if not path.exists():
        raise SystemExit(
            f"[blueprint-reference-harness] missing prebuilt executable `{exe_name}` at {path}. "
            "Refresh this worktree with `python3 -m scripts.blueprint_harness sync-root-lake` "
            "after building from the root checkout, or rerun with `--allow-local-build`."
        )
    return path


def find_prebuilt_lean_test_artifact(package_root: Path) -> Path | None:
    path = package_root / ".lake" / "build" / "lib" / "lean" / "VersoBlueprintTests.olean"
    if path.exists():
        return path
    return None


def lean_test_runner(package_root: Path) -> list[str]:
    return [str(package_root / "scripts" / "run-lean-tests.sh")]


def resolve_repo_relative_path(package_root: Path, path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return package_root / path


def build_in_repo_projects(package_root: Path, projects: list[HarnessProject]) -> None:
    targets = [project.build_target for project in projects if project.build_target is not None]
    if targets:
        run(lean_low_priority_command(package_root, "lake", "build", *targets), cwd=package_root)


def render_in_repo_projects(package_root: Path, output_root: Path, projects: list[HarnessProject], serial: bool) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    if serial:
        for project in projects:
            output_dir = output_dir_for(project, output_root)
            run(
                lean_low_priority_command(
                    package_root,
                    str(ensure_prebuilt_executable(package_root, project.generator or project.project_id)),
                    "--output",
                    str(output_dir),
                ),
                cwd=package_root,
            )
        return

    procs: list[tuple[str, subprocess.Popen[bytes]]] = []
    try:
        for project in projects:
            output_dir = output_dir_for(project, output_root)
            output_dir.mkdir(parents=True, exist_ok=True)
            command = lean_low_priority_command(
                package_root,
                str(ensure_prebuilt_executable(package_root, project.generator or project.project_id)),
                "--output",
                str(output_dir),
            )
            print(f"[blueprint-reference-harness] launching {project.project_id} -> {output_dir}", flush=True)
            procs.append((project.project_id, subprocess.Popen(command, cwd=package_root)))

        failures: list[str] = []
        for project_id, proc in procs:
            if proc.wait() == 0:
                print(f"[blueprint-reference-harness] finished {project_id}")
            else:
                failures.append(project_id)
        if failures:
            raise SystemExit(f"[blueprint-reference-harness] project render failed: {', '.join(failures)}")
    finally:
        for _, proc in procs:
            if proc.poll() is None:
                proc.kill()


def generate_projects(
    layout,
    output_root: Path,
    projects: list[HarnessProject],
    *,
    skip_build: bool,
    serial: bool,
    allow_local_build: bool,
) -> None:
    in_repo_projects = [project for project in projects if project.in_repo_example]
    in_repo_target_projects = [project for project in in_repo_projects if project.in_repo_target_project]
    in_repo_command_projects = [project for project in in_repo_projects if project.in_repo_command_project]
    git_projects = [project for project in projects if project.git_checkout]

    if in_repo_target_projects:
        print(f"[blueprint-reference-harness] package root: {layout.package_root}")
        use_local_build = should_use_local_build(layout, allow_local_build)
        if layout.in_linked_worktree:
            print(f"[blueprint-reference-harness] linked worktree output root: {output_root}")
            if not use_local_build:
                print(
                    "[blueprint-reference-harness] using the current worktree `.lake/`; "
                    "run `sync-root-lake` explicitly when you want to refresh from the root checkout"
                )
        else:
            print(f"[blueprint-reference-harness] output root: {output_root}")

        if not skip_build and use_local_build:
            build_in_repo_projects(layout.package_root, in_repo_target_projects)
        elif not skip_build and not use_local_build:
            for project in in_repo_target_projects:
                ensure_prebuilt_executable(layout.package_root, project.generator or project.project_id)
        render_in_repo_projects(layout.package_root, output_root, in_repo_target_projects, serial)

    if in_repo_command_projects:
        print(f"[blueprint-reference-harness] package root: {layout.package_root}")
        if layout.in_linked_worktree:
            print(f"[blueprint-reference-harness] linked worktree output root: {output_root}")
        else:
            print(f"[blueprint-reference-harness] output root: {output_root}")
        for project in in_repo_command_projects:
            print(f"[blueprint-reference-harness] in-repo project: {project.project_id} ({project.project_root})")
            generate_in_repo_command_project(layout, output_root, project, skip_build=skip_build)

    for project in git_projects:
        print(f"[blueprint-reference-harness] reference checkout: {project.project_id}")
        generate_git_project(layout, output_root, project, skip_build=skip_build)


def panel_regression_command(package_root: Path, project: HarnessProject, site_dir: Path) -> list[str]:
    return [
        sys.executable,
        str(resolve_repo_relative_path(package_root, project.panel_regression_script or "")),
        "--site-dir",
        str(site_dir),
    ]


def browser_test_command(package_root: Path, project: HarnessProject, site_dir: Path, pytest_args: list[str]) -> list[str]:
    tests_path = resolve_repo_relative_path(package_root, project.browser_tests_path or "")
    if shutil.which("uv"):
        command = [
            "env",
            "UV_CACHE_DIR=/tmp/verso-blueprint-uv-cache",
            "uv",
            "run",
            "--project",
            str(tests_path),
            "--extra",
            "test",
            "python",
            "-m",
            "pytest",
        ]
    else:
        command = [sys.executable, "-m", "pytest"]
    return [
        *command,
        str(tests_path),
        "-q",
        "--browser",
        "chromium",
        "--site-dir",
        str(site_dir),
        *pytest_args,
    ]


def command_generate(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    require_safe_root_main(layout, allow_unsafe=args.allow_unsafe_root_release, command_name="generate")
    output_root = resolve_output_root(args.output_root, Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    release_id, projects = select_release_projects(
        catalog,
        release=args.release,
        project_ids=args.project,
        package_root=layout.package_root,
    )
    require_checkout_release(layout, release_id, command_name="generate")

    generate_projects(
        layout,
        output_root,
        projects,
        skip_build=args.skip_build,
        serial=args.serial,
        allow_local_build=args.allow_local_build,
    )

    print(f"[blueprint-reference-harness] project manifest: {manifest_path}")
    print(f"[blueprint-reference-harness] release target: {release_id}")
    print("[blueprint-reference-harness] generated project outputs:")
    for project in projects:
        print(output_dir_for(project, output_root))
    return 0


def command_validate(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    require_safe_root_main(layout, allow_unsafe=args.allow_unsafe_root_release, command_name="validate")
    output_root = resolve_output_root(args.output_root, Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    release_id, projects = select_release_projects(
        catalog,
        release=args.release,
        project_ids=args.project,
        package_root=layout.package_root,
    )
    require_checkout_release(layout, release_id, command_name="validate")
    failures: list[StepFailure] = []

    print(f"[blueprint-reference-harness] validation output root: {output_root}")
    print(f"[blueprint-reference-harness] release target: {release_id}")
    use_local_build = should_use_local_build(layout, args.allow_local_build)
    if args.run_lean_tests:
        if use_local_build:
            failure = run_capturing_failure(
                "lean tests",
                lean_test_runner(layout.package_root),
                cwd=layout.package_root,
            )
            if failure is not None:
                failures.append(failure)
                if args.stop_on_first_failure:
                    return print_failure_summary(failures)
        else:
            test_artifact = find_prebuilt_lean_test_artifact(layout.package_root)
            if test_artifact is None:
                failures.append(
                    StepFailure(
                        "lean tests",
                        "no prebuilt Lean test library found in the current worktree `.lake/`; "
                        "run `python3 -m scripts.blueprint_harness sync-root-lake` after "
                        "building from the root checkout, or use `--allow-local-build`",
                    )
                )
                if args.stop_on_first_failure:
                    return print_failure_summary(failures)
            else:
                print(f"[blueprint-reference-harness] using prebuilt Lean test library: {test_artifact}")

    try:
        generate_projects(
            layout,
            output_root,
            projects,
            skip_build=False,
            serial=args.serial,
            allow_local_build=args.allow_local_build,
        )
    except SystemExit as err:
        failures.append(StepFailure("generate projects", str(err)))
        return print_failure_summary(failures)

    for project in projects:
        site_dir = site_dir_for(project, output_root)
        if project.panel_regression_script is not None and not args.skip_panel_regression:
            failure = run_capturing_failure(
                f"{project.project_id} panel regression",
                panel_regression_command(layout.package_root, project, site_dir),
                cwd=layout.package_root,
            )
            if failure is not None:
                failures.append(failure)
                if args.stop_on_first_failure:
                    return print_failure_summary(failures)

        if project.browser_tests_path is not None and not args.skip_browser_tests:
            failure = run_capturing_failure(
                f"{project.project_id} browser tests",
                browser_test_command(layout.package_root, project, site_dir, args.pytest_arg),
                cwd=layout.package_root,
            )
            if failure is not None:
                failures.append(failure)
                if args.stop_on_first_failure:
                    return print_failure_summary(failures)

    return print_failure_summary(failures)


def command_projects(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    release_id, projects = select_release_projects(
        catalog,
        release=args.release,
        project_ids=args.project,
        package_root=layout.package_root,
    )
    print(f"project_manifest={manifest_path}")
    print(f"release_target={release_id}")
    for project in projects:
        if project.in_repo_example:
            source = f"in_repo:{project.project_root}"
        else:
            source = f"git:{project.repository}@{project.ref}"
        validations: list[str] = []
        if project.panel_regression_script is not None:
            validations.append("panel")
        if project.browser_tests_path is not None:
            validations.append("browser")
        validation_text = ",".join(validations) if validations else "none"
        print(f"{project.project_id}\tsource={source}\tvalidations={validation_text}")
    return 0


def command_status(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    release_id, projects = select_release_projects(
        catalog,
        release=args.release,
        project_ids=args.project,
        package_root=layout.package_root,
    )
    require_checkout_release(layout, release_id, command_name="status")
    release_branch = active_release_branch(layout.repo_root)
    main_status = main_sync_status(layout.repo_root)
    print(f"project_manifest={manifest_path}")
    print(f"selected_release_target={release_id}")
    print(f"verso_blueprint_ref={release_branch}")
    print(f"preferred_release_ref={main_status.upstream_ref}")
    print(f"release_relationship={main_status.relationship}")
    print(f"release_oid={main_status.local_oid or ''}")
    print(f"{main_status.upstream_ref}_oid={main_status.upstream_oid or ''}")

    for project in projects:
        try:
            status = collect_reference_project_status(layout, project)
        except (subprocess.CalledProcessError, json.JSONDecodeError, OSError, ValueError) as err:
            status = ReferenceProjectStatus(
                project=project,
                catalog_ref=None,
                project_upstream_ref=None,
                project_relationship=None,
                project_ahead=None,
                project_behind=None,
                blueprint_pin=None,
                blueprint_relationship=None,
                blueprint_ahead=None,
                blueprint_behind=None,
                error=str(err),
            )
        print_reference_project_status(status)
    return 0


def command_release_status(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    releases = selected_release_targets(catalog, args.release, layout.package_root)
    known_project_ids = {project.project_id for project in catalog.projects}
    if args.project is not None:
        unknown = sorted({value for value in args.project if value not in known_project_ids})
        if unknown:
            known = ", ".join(sorted(known_project_ids))
            raise SystemExit(
                f"[blueprint-reference-harness] unknown project(s) {', '.join(unknown)}; known projects: {known}"
            )

    print(f"project_manifest={manifest_path}")
    for release_target in releases:
        projects = resolve_projects_for_release(catalog, release_target.release_id, None)
        if args.project is not None:
            allowed = set(args.project)
            projects = [project for project in projects if project.project_id in allowed]

        statuses: list[ReferenceProjectStatus] = []
        for project in projects:
            try:
                status = collect_reference_project_status(
                    layout,
                    project,
                    blueprint_base_ref=release_target.branch,
                )
            except (subprocess.CalledProcessError, json.JSONDecodeError, OSError, ValueError) as err:
                status = ReferenceProjectStatus(
                    project=project,
                    catalog_ref=None,
                    project_upstream_ref=None,
                    project_relationship=None,
                    project_ahead=None,
                    project_behind=None,
                    blueprint_pin=None,
                    blueprint_relationship=None,
                    blueprint_ahead=None,
                    blueprint_behind=None,
                    error=str(err),
                )
            statuses.append(status)

        summary = ReleaseTargetStatus(
            release_id=release_target.release_id,
            toolchain=release_target.toolchain,
            verso_ref=release_target.verso_ref,
            branch=release_target.branch,
            deploy_pages=release_target.deploy_pages,
            project_statuses=tuple(statuses),
        )
        if args.outdated_only and not any(status_has_catalog_issue(status) for status in summary.project_statuses):
            continue

        print_release_target_summary(summary)
        for status in summary.project_statuses:
            if args.outdated_only and not status_has_catalog_issue(status):
                continue
            print_release_target_project_status(release_target.release_id, status)
    return 0


def command_reference_sync(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    require_safe_root_main(layout, allow_unsafe=args.allow_unsafe_root_release, command_name="sync")
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    release_id, projects = select_release_projects(
        catalog,
        release=args.release,
        project_ids=args.project,
        package_root=layout.package_root,
    )
    require_checkout_release(layout, release_id, command_name="sync")
    sync_reference_blueprints(
        layout,
        projects,
        warm_build=not args.skip_build,
        prepare_local_checkout=not args.skip_local_checkout,
    )
    print(f"[blueprint-reference-harness] release target: {release_id}")
    print(f"[blueprint-reference-harness] reference cache root: {layout.reference_project_cache_root}")
    print(f"[blueprint-reference-harness] reference checkout root: {layout.reference_project_checkout_root}")
    return 0


def command_reference_edit(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    project_map = {project.project_id: project for project in catalog.projects}
    if args.project not in project_map:
        known = ", ".join(sorted(project_map))
        raise SystemExit(f"[blueprint-reference-harness] unknown project `{args.project}`; known projects: {known}")
    project = project_map[args.project]
    edit_dir, branch, base_ref = prepare_reference_edit_checkout(
        layout,
        project,
        branch=args.branch,
        base_ref=args.base,
    )
    print(f"[blueprint-reference-harness] editable reference checkout: {edit_dir}")
    print(f"[blueprint-reference-harness] branch: {branch}")
    print(f"[blueprint-reference-harness] base ref: {base_ref}")
    print(
        "[blueprint-reference-harness] note: editable reference checkouts are separate from the "
        "disposable validation clones used by `sync` and `generate`."
    )
    return 0


def command_reference_bump_blueprint(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    project_map = {project.project_id: project for project in catalog.projects if project.git_checkout}
    if args.project:
        seen: set[str] = set()
        projects: list[HarnessProject] = []
        for value in args.project:
            if value not in project_map:
                known = ", ".join(sorted(project_map))
                raise SystemExit(f"[blueprint-reference-harness] unknown project `{value}`; known projects: {known}")
            if value not in seen:
                projects.append(project_map[value])
                seen.add(value)
    else:
        projects = list(project_map.values())
    failures: list[StepFailure] = []
    output_root = layout.artifact_root / "reference-blueprints-edit"

    for project in projects:
        print(f"[blueprint-reference-harness] bumping {project.project_id} to {args.ref}")
        try:
            result = bump_reference_project(
                layout,
                project,
                ref=args.ref,
                branch=args.branch,
                base_ref=args.base,
                build_project=not args.skip_build,
                generate_site=args.generate,
                output_root=output_root,
                commit=args.commit or args.push,
                push=args.push,
                commit_message=args.commit_message,
            )
        except subprocess.CalledProcessError as err:
            command = [str(part) for part in (err.cmd if isinstance(err.cmd, list) else [err.cmd])]
            failures.append(
                StepFailure(
                    step=f"{project.project_id} bump",
                    detail=f"exit code {err.returncode}: {format_command(command)}",
                )
            )
            continue
        except SystemExit as err:
            failures.append(StepFailure(step=f"{project.project_id} bump", detail=str(err)))
            continue

        previous_ref = result.previous_ref or "<none>"
        print(f"[blueprint-reference-harness] editable reference checkout: {result.edit_dir}")
        print(f"[blueprint-reference-harness] branch: {result.branch}")
        print(f"[blueprint-reference-harness] base ref: {result.base_ref}")
        print(f"[blueprint-reference-harness] pinned ref: {previous_ref} -> {args.ref}")
        if result.output_dir is not None:
            print(f"[blueprint-reference-harness] generated output: {result.output_dir}")
        if not result.changed:
            print(
                "[blueprint-reference-harness] note: no tracked downstream changes remain after the pin rewrite/update"
            )
        elif args.commit and not result.committed and not args.push:
            print("[blueprint-reference-harness] note: tracked changes were left uncommitted")
        if result.committed:
            print("[blueprint-reference-harness] committed tracked downstream changes")
        if result.pushed:
            print("[blueprint-reference-harness] pushed editable branch to origin")

    return print_failure_summary(failures)


def command_reference_prune(args: argparse.Namespace) -> int:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    projects = load_project_catalog(manifest_path).projects
    active_names = {
        root_checkout_namespace(layout.repo_root) if worktree.root_checkout else worktree.name
        for worktree in git_worktrees(layout.repo_root)
    }
    project_ids = {project.project_id for project in projects if project.git_checkout}
    removals = reference_prune_plan(
        active_names,
        project_ids,
        layout.reference_project_cache_root,
        layout.reference_project_root / "by-worktree",
    )
    if not removals:
        print("[blueprint-reference-harness] reference prune: no stale cached checkouts found")
        return 0
    for path in removals:
        print(path)
    if args.dry_run:
        return 0
    for path in removals:
        shutil.rmtree(path)
    print(f"[blueprint-reference-harness] reference prune: removed {len(removals)} path(s)")
    return 0

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python3 -m scripts.blueprint_reference_harness",
        description="Reference blueprint generation, validation, and checkout lifecycle CLI.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser(
        "generate",
        help="Build the selected blueprint harness projects.",
    )
    add_output_root_argument(generate)
    add_project_selection_argument(generate, help_text="Render only the selected project. Repeat to render more than one.")
    add_manifest_argument(generate)
    generate.add_argument("--release", default=None, help="Release target to validate. Defaults to the current checkout release line.")
    generate.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip project builds and only run already-built or command-only generation steps.",
    )
    add_allow_unsafe_root_main_argument(generate)
    add_serial_argument(generate)
    add_allow_local_build_argument(
        generate,
        help_text="Permit `lake build` in a linked worktree instead of requiring synced root executables.",
    )
    generate.set_defaults(func=command_generate)

    validate = subparsers.add_parser(
        "validate",
        help="Generate selected projects and run configured regressions.",
    )
    add_output_root_argument(validate)
    add_project_selection_argument(validate, help_text="Restrict generation to the selected project. Repeat to select more.")
    add_manifest_argument(validate)
    validate.add_argument("--release", default=None, help="Release target to validate. Defaults to the current checkout release line.")
    validate.add_argument(
        "--run-lean-tests",
        action="store_true",
        help="Also run this repository's Lean tests before project generation.",
    )
    validate.add_argument(
        "--skip-panel-regression",
        action="store_true",
        help="Skip configured static panel regression checks.",
    )
    validate.add_argument(
        "--skip-browser-tests",
        action="store_true",
        help="Skip configured Playwright browser regression suites.",
    )
    add_allow_unsafe_root_main_argument(validate)
    add_serial_argument(validate)
    validate.add_argument(
        "--pytest-arg",
        action="append",
        default=[],
        help="Extra argument forwarded to pytest. Repeat for multiple arguments.",
    )
    add_allow_local_build_argument(
        validate,
        help_text="Permit `lake build` and `lake test` in a linked worktree instead of requiring synced root artifacts.",
    )
    validate.add_argument(
        "--stop-on-first-failure",
        action="store_true",
        help="Stop validation as soon as one phase fails instead of collecting later failures.",
    )
    validate.set_defaults(func=command_validate)

    projects = subparsers.add_parser(
        "projects",
        help="List the configured harness projects from the active manifest.",
    )
    add_manifest_argument(projects)
    add_project_selection_argument(
        projects,
        help_text="Restrict output to the selected project. Repeat to select more.",
        include_example_alias=False,
    )
    projects.add_argument("--release", default=None, help="Release target to list. Defaults to the current checkout release line.")
    projects.set_defaults(func=command_projects)

    status = subparsers.add_parser(
        "status",
        help="Report reference-project catalog drift and committed `VersoBlueprint` pin drift.",
    )
    add_manifest_argument(status)
    add_project_selection_argument(
        status,
        help_text="Restrict status output to the selected project. Repeat to select more.",
        include_example_alias=False,
    )
    status.add_argument("--release", default=None, help="Release target to inspect. Defaults to the current checkout release line.")
    status.set_defaults(func=command_status)

    release_status = subparsers.add_parser(
        "release-status",
        help="Summarize release-target compatibility coverage and detect outdated reference targets.",
    )
    add_manifest_argument(release_status)
    add_project_selection_argument(
        release_status,
        help_text="Restrict output to the selected project. Repeat to select more.",
        include_example_alias=False,
    )
    release_status.add_argument(
        "--release",
        default=None,
        help="Release target to inspect. Defaults to all declared release targets.",
    )
    release_status.add_argument(
        "--outdated-only",
        action="store_true",
        help="Print only release targets and projects with drift or errors.",
    )
    release_status.set_defaults(func=command_release_status)

    sync = subparsers.add_parser(
        "sync",
        help="Warm shared reference blueprint caches and prepare local clones for the current checkout.",
    )
    add_manifest_argument(sync)
    add_project_selection_argument(
        sync,
        help_text="Restrict sync to the selected project. Repeat to select more.",
        include_example_alias=False,
    )
    sync.add_argument("--release", default=None, help="Release target to sync. Defaults to the current checkout release line.")
    sync.add_argument(
        "--skip-build",
        action="store_true",
        help="Update and clone the reference projects without warming their build artifacts.",
    )
    add_allow_unsafe_root_main_argument(sync)
    sync.add_argument(
        "--skip-local-checkout",
        action="store_true",
        help="Warm only the shared cache checkout and skip preparing the current checkout's local clones.",
    )
    sync.set_defaults(func=command_reference_sync)

    edit = subparsers.add_parser(
        "edit",
        help="Prepare or reuse one editable external reference checkout for manual changes.",
    )
    add_manifest_argument(edit)
    edit.add_argument("project", help="External git-checkout project id to open for editing.")
    edit.add_argument(
        "--branch",
        default=None,
        help="Editable branch name. Defaults to `wip/<project-id>`.",
    )
    edit.add_argument(
        "--base",
        default=None,
        help="Base ref used when creating the editable branch. Defaults to `origin/<project-ref>`.",
    )
    edit.set_defaults(func=command_reference_edit)

    bump = subparsers.add_parser(
        "bump-verso-blueprint",
        help="Rewrite the pinned `VersoBlueprint` ref in editable external reference checkouts.",
    )
    add_manifest_argument(bump)
    add_project_selection_argument(
        bump,
        help_text="Restrict the bump to the selected external project. Repeat to select more.",
        include_example_alias=False,
    )
    bump.add_argument(
        "--ref",
        required=True,
        help="New `VersoBlueprint` git ref, tag, or commit to pin in the downstream project.",
    )
    bump.add_argument(
        "--branch",
        default=None,
        help="Editable branch name. Defaults to `chore/bump-verso-blueprint-<ref>`.",
    )
    bump.add_argument(
        "--base",
        default=None,
        help="Base ref used when creating the editable branch. Defaults to `origin/<project-ref>`.",
    )
    bump.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip downstream project builds after rewriting the dependency pin.",
    )
    bump.add_argument(
        "--generate",
        action="store_true",
        help="Also render the downstream site under `_out/.../reference-blueprints-edit/<project>/` after bumping.",
    )
    bump.add_argument(
        "--commit",
        action="store_true",
        help="Create one commit with the rewritten pin and tracked manifest updates when there are tracked changes.",
    )
    bump.add_argument(
        "--push",
        action="store_true",
        help="Push the editable branch to `origin` after committing. Implies `--commit`.",
    )
    bump.add_argument(
        "--commit-message",
        default=None,
        help="Commit message to use with `--commit`. Defaults to `chore: bump VersoBlueprint to <ref>`.",
    )
    bump.set_defaults(func=command_reference_bump_blueprint)

    prune = subparsers.add_parser(
        "prune",
        help="Remove stale harness-managed reference blueprint caches and checkout clones.",
    )
    add_manifest_argument(prune)
    prune.add_argument(
        "--dry-run",
        action="store_true",
        help="List stale paths without deleting them.",
    )
    prune.set_defaults(func=command_reference_prune)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

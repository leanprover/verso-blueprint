#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_branches import load_branch_policy
from scripts.blueprint_harness_paths import detect_harness_layout
from scripts.blueprint_harness_projects import (
    deploy_matrix_from_controller_catalog,
    load_project_catalog,
    resolve_manifest_path,
)
from scripts.reference_artifact_identity import resolve_branch_revision


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit deployable reference-release metadata for the Pages deployment workflow."
    )
    parser.add_argument(
        "--manifest",
        default=None,
        help="Project manifest path. Defaults to tests/harness/projects.json in the current checkout.",
    )
    parser.add_argument(
        "--github-output",
        action="store_true",
        help="Print GitHub Actions step outputs instead of plain JSON.",
    )
    parser.add_argument(
        "--validated-push", nargs=2, metavar=("BRANCH", "SHA"),
        help="Admit automatic publication only after every published head has a successful push run.",
    )
    return parser.parse_args()


def has_successful_push(repository: str, branch: str, revision: str) -> bool:
    response = subprocess.check_output(
        [
            "gh", "api", "--method", "GET",
            f"repos/{repository}/actions/workflows/reference-blueprints.yml/runs",
            "-f", "event=push", "-f", f"branch={branch}", "-f", f"head_sha={revision}",
            "-F", "per_page=1",
        ],
        text=True,
    )
    runs = json.loads(response)["workflow_runs"]
    if not runs:
        return False
    run = runs[0]
    return (
        run["conclusion"] == "success"
        and run["event"] == "push"
        and run["head_branch"] == branch
        and run["head_sha"] == revision
        and (run["head_repository"] or {}).get("full_name") == repository
    )


def automatic_deploy_skip_reason(
    revisions: dict[str, str],
    branch: str,
    revision: str,
    *,
    repository: str,
    controller_branch: str,
    controller_revision: str,
) -> str | None:
    if branch not in revisions:
        return f"{branch} is outside the published release catalog"
    if revisions[branch] != revision:
        return f"{branch} has moved since validation of {revision}"
    if revisions.get(controller_branch, controller_revision) != controller_revision:
        return f"the controller checkout does not match the release head for {controller_branch}"
    required = {**revisions, controller_branch: controller_revision}
    for other, head in required.items():
        if other != branch and not has_successful_push(repository, other, head):
            return f"waiting for successful push validation of {other} at {head}"
    return None


def payload(args: argparse.Namespace) -> dict[str, object]:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    deployable_targets = tuple(
        target
        for target in catalog.release_targets
        if target.deploy_pages
    )
    policy = load_branch_policy(layout.package_root)
    matrix = deploy_matrix_from_controller_catalog(
        catalog,
        deployable_targets,
        pdf_release_id=policy.default_dev_branch,
    )
    revisions = {
        target.branch: resolve_branch_revision(layout.package_root, target.branch)
        for target in deployable_targets
    }
    if args.validated_push:
        controller_revision = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=layout.package_root, text=True,
        ).strip()
        reason = automatic_deploy_skip_reason(
            revisions, *args.validated_push, repository=os.environ["GITHUB_REPOSITORY"],
            controller_branch=policy.default_dev_branch, controller_revision=controller_revision,
        )
        if reason:
            print(f"Skipping reference publication: {reason}.", file=sys.stderr)
            matrix = {"include": []}
    for entry in matrix["include"]:
        entry["generator_revision"] = revisions[entry["branch"]]
    deployable_release_count = len({entry["release_id"] for entry in matrix["include"]})
    return {
        "manifest_path": str(manifest_path),
        "deployable_release_count": deployable_release_count,
        "deployable_project_count": len(matrix["include"]),
        "deployable_project_matrix": matrix,
    }


def emit_github_output(data: dict[str, object]) -> None:
    print(f"manifest_path={data['manifest_path']}")
    print(f"deployable_release_count={data['deployable_release_count']}")
    print(f"deployable_project_count={data['deployable_project_count']}")
    print("deployable_project_matrix<<__CODEX__")
    print(json.dumps(data["deployable_project_matrix"], separators=(",", ":")))
    print("__CODEX__")


def main() -> int:
    args = parse_args()
    data = payload(args)
    if args.github_output:
        emit_github_output(data)
    else:
        print(json.dumps(data, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

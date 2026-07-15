#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_paths import detect_harness_layout
from scripts.blueprint_harness_branches import load_branch_policy
from scripts.blueprint_harness_projects import (
    deploy_matrix_from_controller_catalog,
    load_project_catalog,
    resolve_manifest_path,
)


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
    return parser.parse_args()


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

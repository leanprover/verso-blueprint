#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_paths import detect_harness_layout
from scripts.blueprint_harness_projects import (
    load_project_catalog,
    load_project_catalog_data,
    reference_release_payload,
    resolve_manifest_path,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit release-aware reference blueprint metadata for CI workflows."
    )
    parser.add_argument(
        "--manifest",
        default=None,
        help="Project manifest path. Defaults to tests/harness/projects.json in the current checkout.",
    )
    parser.add_argument(
        "--controller-policy",
        default=None,
        help="Release policy fetched with a controller catalog, rather than the checkout's policy.",
    )
    parser.add_argument(
        "--release",
        default=None,
        help="Release target id. Defaults to the current checkout release line.",
    )
    parser.add_argument(
        "--github-output",
        action="store_true",
        help="Print GitHub Actions step outputs instead of plain JSON.",
    )
    return parser.parse_args()


def load_catalog(manifest_path: Path, controller_policy: Path | None = None):
    if controller_policy is None:
        return load_project_catalog(manifest_path)
    raw = json.loads(manifest_path.read_text(encoding="utf-8"))
    policy = json.loads(controller_policy.read_text(encoding="utf-8"))
    # A fetched catalog must be interpreted with its own release definitions.
    # Keep the local package root for in-repo fixtures and build paths.
    raw["release_targets"] = policy["release_targets"]
    return load_project_catalog_data(raw, manifest_path)


def payload(args: argparse.Namespace) -> dict[str, object]:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    policy = Path(args.controller_policy).resolve() if args.controller_policy else None
    catalog = load_catalog(manifest_path, policy)
    return reference_release_payload(manifest_path, catalog, args.release, layout.package_root)


def emit_github_output(data: dict[str, object]) -> None:
    print(f"manifest_path={data['manifest_path']}")
    print(f"release_id={data['release_id']}")
    print(f"rc={data['rc'] or ''}")
    print(f"toolchain={data['toolchain']}")
    print(f"verso_ref={data['verso_ref']}")
    print(f"branch={data['branch']}")
    print(f"deploy_pages={str(data['deploy_pages']).lower()}")
    print(f"reference_project_count={data['reference_project_count']}")
    print("reference_matrix<<__CODEX__")
    print(json.dumps(data["reference_matrix"], separators=(",", ":")))
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

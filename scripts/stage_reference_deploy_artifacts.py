#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_projects import DEPLOY_PROJECT_ARTIFACT_SEPARATOR
from scripts.reference_artifact_identity import (
    IDENTITY_FILENAME,
    IDENTITY_VERSION,
    load_json_object,
    validate_identity_envelope,
)


ARTIFACT_PREFIX = "reference-blueprints-release-"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stage downloaded per-project deploy artifacts into a release-organized reference tree."
    )
    parser.add_argument(
        "--artifacts-root",
        default="_out/reference-artifact-downloads",
        help="Directory populated by actions/download-artifact with one subdirectory per artifact.",
    )
    parser.add_argument(
        "--output-root",
        default="_out/reference-blueprints",
        help="Directory where the combined reference blueprint tree should be rebuilt.",
    )
    parser.add_argument(
        "--expected-identities",
        default="_out/expected-reference-artifacts.json",
        help="Exact artifact identities generated from the current deploy matrix and release branch heads.",
    )
    return parser.parse_args()


def parse_artifact_name(name: str) -> tuple[str, str] | None:
    if not name.startswith(ARTIFACT_PREFIX):
        return None
    payload = name.removeprefix(ARTIFACT_PREFIX)
    release_id, separator, project_id = payload.partition(DEPLOY_PROJECT_ARTIFACT_SEPARATOR)
    if not separator or not release_id or not project_id:
        raise SystemExit(f"invalid deploy reference artifact name: {name}")
    return release_id, project_id


def resolve_artifact_project_root(artifact_dir: Path, release_id: str, project_id: str) -> Path:
    candidates = (
        artifact_dir,
        artifact_dir / project_id,
        artifact_dir / release_id / project_id,
    )
    for candidate in candidates:
        if (candidate / "html-multi").exists():
            return candidate
    raise SystemExit(
        f"artifact `{artifact_dir.name}` did not contain a recognizable `{project_id}` site payload"
    )


def load_expected_identities(path: Path) -> dict[str, dict[str, object]]:
    value = load_json_object(path)
    if value.get("version") != IDENTITY_VERSION:
        raise SystemExit(f"unsupported expected reference artifact identity version in `{path}`")
    artifacts = value.get("artifacts")
    if not isinstance(artifacts, dict):
        raise SystemExit(f"expected reference artifact identities in `{path}` must contain an `artifacts` object")

    expected: dict[str, dict[str, object]] = {}
    for artifact_name, envelope in artifacts.items():
        if not isinstance(artifact_name, str) or not isinstance(envelope, dict):
            raise SystemExit(f"invalid expected reference artifact identity in `{path}`")
        try:
            expected[artifact_name] = validate_identity_envelope(
                envelope,
                context=f"expected artifact `{artifact_name}`",
            )
        except ValueError as err:
            raise SystemExit(str(err)) from err
    if not expected:
        raise SystemExit(f"expected reference artifact identity set in `{path}` is empty")
    return expected


def stage_artifacts(artifacts_root: Path, output_root: Path, expected_identities_path: Path) -> None:
    if not artifacts_root.exists():
        raise SystemExit(f"missing downloaded reference artifact root: {artifacts_root}")

    expected = load_expected_identities(expected_identities_path)
    validated: list[tuple[str, str, Path]] = []
    found: set[str] = set()
    for artifact_dir in sorted(path for path in artifacts_root.iterdir() if path.is_dir()):
        parsed = parse_artifact_name(artifact_dir.name)
        if parsed is None:
            continue
        if artifact_dir.name not in expected:
            raise SystemExit(f"unexpected deploy reference artifact: {artifact_dir.name}")
        release_id, project_id = parsed
        source_root = resolve_artifact_project_root(artifact_dir, release_id, project_id)
        metadata_path = source_root / IDENTITY_FILENAME
        try:
            actual = validate_identity_envelope(
                load_json_object(metadata_path),
                context=f"artifact `{artifact_dir.name}`",
            )
        except ValueError as err:
            raise SystemExit(str(err)) from err
        if actual != expected[artifact_dir.name]:
            raise SystemExit(
                f"artifact `{artifact_dir.name}` identity does not match the current catalog and release branch"
            )
        identity = actual["identity"]
        if identity["release_id"] != release_id or identity["project_id"] != project_id:
            raise SystemExit(f"artifact `{artifact_dir.name}` identity does not match its artifact name")
        validated.append((release_id, project_id, source_root))
        found.add(artifact_dir.name)

    missing = sorted(set(expected) - found)
    if missing:
        raise SystemExit(f"missing deploy reference artifacts: {', '.join(missing)}")

    if output_root.exists():
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    for release_id, project_id, source_root in validated:
        destination = output_root / release_id / project_id
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source_root, destination, ignore=shutil.ignore_patterns(IDENTITY_FILENAME))


def main() -> int:
    args = parse_args()
    artifacts_root = Path(args.artifacts_root).resolve()
    output_root = Path(args.output_root).resolve()
    expected_identities_path = Path(args.expected_identities).resolve()
    stage_artifacts(artifacts_root, output_root, expected_identities_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

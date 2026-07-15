#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


IDENTITY_VERSION = 1
IDENTITY_FILENAME = "reference-blueprint-artifact.json"
REVISION_RE = re.compile(r"[0-9a-f]{40,64}")


def load_json_object(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as err:
        raise ValueError(f"could not read JSON object `{path}`: {err}") from err
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object in `{path}`")
    return value


def canonical_sha256(value: object) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def artifact_identity(
    project_manifest: dict[str, object],
    *,
    release_id: str,
    project_id: str,
    generator_revision: str,
) -> dict[str, object]:
    if not release_id or not project_id:
        raise ValueError("artifact identity requires non-empty release and project ids")
    if REVISION_RE.fullmatch(generator_revision) is None:
        raise ValueError(f"invalid generator revision `{generator_revision}`")

    projects = project_manifest.get("projects")
    if not isinstance(projects, list) or len(projects) != 1 or not isinstance(projects[0], dict):
        raise ValueError("artifact project manifest must contain exactly one project")
    if projects[0].get("id") != project_id:
        raise ValueError(
            f"artifact project id `{project_id}` does not match manifest project `{projects[0].get('id')}`"
        )

    targets = projects[0].get("targets")
    if not isinstance(targets, list) or len(targets) != 1 or not isinstance(targets[0], dict):
        raise ValueError("artifact project manifest must contain exactly one project target")
    if targets[0].get("release") != release_id:
        raise ValueError(
            f"artifact release `{release_id}` does not match manifest target `{targets[0].get('release')}`"
        )

    return {
        "version": IDENTITY_VERSION,
        "release_id": release_id,
        "project_id": project_id,
        "generator_revision": generator_revision,
        "project_manifest": project_manifest,
    }


def identity_envelope(identity: dict[str, object]) -> dict[str, object]:
    return {
        "sha256": canonical_sha256(identity),
        "identity": identity,
    }


def validate_identity_envelope(value: dict[str, object], *, context: str) -> dict[str, object]:
    if set(value) != {"identity", "sha256"}:
        raise ValueError(f"{context}: expected exactly `identity` and `sha256` fields")
    identity = value.get("identity")
    digest = value.get("sha256")
    if not isinstance(identity, dict) or not isinstance(digest, str):
        raise ValueError(f"{context}: expected `identity` object and `sha256` string")
    actual = canonical_sha256(identity)
    if digest != actual:
        raise ValueError(f"{context}: identity digest mismatch: expected `{digest}`, computed `{actual}`")

    release_id = identity.get("release_id")
    project_id = identity.get("project_id")
    generator_revision = identity.get("generator_revision")
    project_manifest = identity.get("project_manifest")
    if not isinstance(release_id, str) or not isinstance(project_id, str):
        raise ValueError(f"{context}: identity release and project ids must be strings")
    if not isinstance(generator_revision, str) or not isinstance(project_manifest, dict):
        raise ValueError(f"{context}: identity generator revision and project manifest are invalid")
    try:
        validated = artifact_identity(
            project_manifest,
            release_id=release_id,
            project_id=project_id,
            generator_revision=generator_revision,
        )
    except ValueError as err:
        raise ValueError(f"{context}: {err}") from err
    if identity != validated:
        raise ValueError(f"{context}: identity contains unexpected or inconsistent fields")
    return value


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def install_identity(identity_path: Path, artifact_root: Path) -> Path:
    expected = validate_identity_envelope(load_json_object(identity_path), context=str(identity_path))
    artifact_root.mkdir(parents=True, exist_ok=True)
    destination = artifact_root / IDENTITY_FILENAME
    write_json(destination, expected)
    return destination


def validate_artifact_identity(identity_path: Path, artifact_root: Path) -> None:
    expected = validate_identity_envelope(load_json_object(identity_path), context=str(identity_path))
    metadata_path = artifact_root / IDENTITY_FILENAME
    actual = validate_identity_envelope(load_json_object(metadata_path), context=str(metadata_path))
    if actual != expected:
        raise ValueError(f"artifact `{artifact_root}` identity does not match the current catalog and generator")


def resolve_branch_revision(repo_root: Path, branch: str) -> str:
    candidates = (f"refs/remotes/origin/{branch}", f"refs/heads/{branch}", branch)
    for candidate in candidates:
        result = subprocess.run(
            ["git", "rev-parse", "--verify", candidate],
            cwd=repo_root,
            text=True,
            capture_output=True,
            check=False,
        )
        revision = result.stdout.strip()
        if result.returncode == 0 and REVISION_RE.fullmatch(revision) is not None:
            return revision
    raise ValueError(f"could not resolve generator revision for release branch `{branch}`")


def expected_identities_from_matrix(matrix: dict[str, object], repo_root: Path) -> dict[str, object]:
    include = matrix.get("include")
    if not isinstance(include, list):
        raise ValueError("deploy matrix must contain an `include` list")

    artifacts: dict[str, object] = {}
    revisions: dict[str, str] = {}
    for index, entry in enumerate(include):
        if not isinstance(entry, dict):
            raise ValueError(f"deploy matrix entry #{index} must be an object")
        required = ("artifact_name", "release_id", "project_id", "branch", "project_manifest")
        if any(key not in entry for key in required):
            raise ValueError(f"deploy matrix entry #{index} is missing artifact identity fields")
        artifact_name = entry["artifact_name"]
        release_id = entry["release_id"]
        project_id = entry["project_id"]
        branch = entry["branch"]
        project_manifest = entry["project_manifest"]
        if not all(isinstance(value, str) for value in (artifact_name, release_id, project_id, branch)):
            raise ValueError(f"deploy matrix entry #{index} has non-string identity fields")
        if not isinstance(project_manifest, dict):
            raise ValueError(f"deploy matrix entry #{index} has invalid project manifest")
        if artifact_name in artifacts:
            raise ValueError(f"duplicate deploy artifact name `{artifact_name}`")
        if branch not in revisions:
            revisions[branch] = resolve_branch_revision(repo_root, branch)
        revision = revisions[branch]
        identity = artifact_identity(
            project_manifest,
            release_id=release_id,
            project_id=project_id,
            generator_revision=revision,
        )
        artifacts[artifact_name] = identity_envelope(identity)
    return {"version": IDENTITY_VERSION, "artifacts": artifacts}


def command_create(args: argparse.Namespace) -> int:
    project_manifest = load_json_object(Path(args.manifest))
    envelope = identity_envelope(
        artifact_identity(
            project_manifest,
            release_id=args.release_id,
            project_id=args.project_id,
            generator_revision=args.generator_revision,
        )
    )
    write_json(Path(args.output), envelope)
    if args.github_output:
        print(f"sha256={envelope['sha256']}")
    return 0


def command_install(args: argparse.Namespace) -> int:
    install_identity(Path(args.identity), Path(args.artifact_root))
    return 0


def command_validate(args: argparse.Namespace) -> int:
    validate_artifact_identity(Path(args.identity), Path(args.artifact_root))
    return 0


def command_expected_matrix(args: argparse.Namespace) -> int:
    try:
        matrix = json.loads(args.matrix_json)
    except json.JSONDecodeError as err:
        raise ValueError(f"invalid deploy matrix JSON: {err}") from err
    if not isinstance(matrix, dict):
        raise ValueError("deploy matrix JSON must be an object")
    expected = expected_identities_from_matrix(matrix, Path(args.repo_root))
    write_json(Path(args.output), expected)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create and validate exact reference artifact identities.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create")
    create.add_argument("--manifest", required=True)
    create.add_argument("--release-id", required=True)
    create.add_argument("--project-id", required=True)
    create.add_argument("--generator-revision", required=True)
    create.add_argument("--output", required=True)
    create.add_argument("--github-output", action="store_true")
    create.set_defaults(func=command_create)

    install = subparsers.add_parser("install")
    install.add_argument("--identity", required=True)
    install.add_argument("--artifact-root", required=True)
    install.set_defaults(func=command_install)

    validate = subparsers.add_parser("validate")
    validate.add_argument("--identity", required=True)
    validate.add_argument("--artifact-root", required=True)
    validate.set_defaults(func=command_validate)

    expected = subparsers.add_parser("expected-matrix")
    expected.add_argument("--matrix-json", required=True)
    expected.add_argument("--repo-root", default=".")
    expected.add_argument("--output", required=True)
    expected.set_defaults(func=command_expected_matrix)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return args.func(args)
    except ValueError as err:
        raise SystemExit(str(err)) from err


if __name__ == "__main__":
    raise SystemExit(main())

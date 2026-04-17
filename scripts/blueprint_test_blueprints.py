from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re

from scripts.blueprint_harness_paths import detect_harness_layout
from scripts.blueprint_harness_references import (
    maybe_rewrite_in_repo_blueprint_dependency,
    reference_update_command,
    restore_tracked_project_manifest,
    snapshot_tracked_project_manifest,
)
from scripts.blueprint_harness_utils import lean_low_priority_command, rebuild_embedded_asset_owners, run


TAG_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


@dataclass(frozen=True)
class StandaloneTestBlueprint:
    slug: str
    title: str
    category: str
    summary: str
    tags: tuple[str, ...]
    project_root: str
    build_command: tuple[str, ...] | None
    generate_command: tuple[str, ...]
    panel_regression_script: str | None
    browser_tests_path: str | None

    @property
    def kind(self) -> str:
        return "standalone_project"

    @property
    def meta(self) -> dict[str, str]:
        return {
            "slug": self.slug,
            "title": self.title,
            "category": self.category,
            "summary": self.summary,
            "tags": list(self.tags),
            "kind": self.kind,
        }


def default_test_blueprint_manifest(package_root: Path) -> Path:
    return package_root / "tests" / "harness" / "test_blueprints.json"


def resolve_test_blueprint_manifest(path_text: str | None, package_root: Path) -> Path:
    if path_text is None:
        return default_test_blueprint_manifest(package_root)
    path = Path(path_text)
    if path.is_absolute():
        return path.resolve()
    return (Path.cwd() / path).resolve()


def _require_string(data: dict, key: str, *, context: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f"{context}: expected non-empty string field `{key}`")
    return value


def _optional_string(data: dict, key: str, *, context: str) -> str | None:
    value = data.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise ValueError(f"{context}: expected non-empty string field `{key}`")
    return value


def _optional_command(data: dict, key: str, *, context: str) -> tuple[str, ...] | None:
    value = data.get(key)
    if value is None:
        return None
    if not isinstance(value, list) or not value or not all(isinstance(item, str) and item for item in value):
        raise ValueError(f"{context}: expected non-empty string list field `{key}`")
    return tuple(value)


def _required_string_list(data: dict, key: str, *, context: str) -> tuple[str, ...]:
    value = data.get(key)
    if not isinstance(value, list) or not value or not all(isinstance(item, str) and item for item in value):
        raise ValueError(f"{context}: expected non-empty string list field `{key}`")
    if len(set(value)) != len(value):
        raise ValueError(f"{context}: duplicate values in `{key}`")
    return tuple(value)


def _optional_tags(data: dict, key: str, *, context: str) -> tuple[str, ...]:
    value = data.get(key)
    if value is None:
        return ()
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise ValueError(f"{context}: expected string list field `{key}`")
    tags = tuple(value)
    if len(set(tags)) != len(tags):
        raise ValueError(f"{context}: duplicate values in `{key}`")
    invalid = [tag for tag in tags if not TAG_PATTERN.fullmatch(tag)]
    if invalid:
        raise ValueError(f"{context}: invalid tag values in `{key}`: {', '.join(invalid)}")
    return tags


def load_test_blueprint_catalog(manifest_path: Path) -> tuple[tuple[str, ...], list[StandaloneTestBlueprint]]:
    raw = json.loads(manifest_path.read_text(encoding="utf-8"))
    if raw.get("version") != 1:
        raise ValueError(f"{manifest_path}: unsupported manifest version {raw.get('version')!r}")

    categories = _required_string_list(raw, "categories", context=str(manifest_path))

    entries = raw.get("fixtures")
    if not isinstance(entries, list):
        raise ValueError(f"{manifest_path}: expected top-level `fixtures` list")

    seen_slugs: set[str] = set()
    fixtures: list[StandaloneTestBlueprint] = []
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"{manifest_path}: fixture #{index} must be an object")
        context = f"{manifest_path}: fixture #{index}"
        slug = _require_string(entry, "slug", context=context)
        if slug in seen_slugs:
            raise ValueError(f"{context}: duplicate fixture slug `{slug}`")
        seen_slugs.add(slug)
        title = _require_string(entry, "title", context=context)
        category = _require_string(entry, "category", context=context)
        if category not in categories:
            raise ValueError(f"{context}: unknown category `{category}`")
        summary = _require_string(entry, "summary", context=context)
        tags = _optional_tags(entry, "tags", context=context)
        project_root = _require_string(entry, "project_root", context=context)
        build_command = _optional_command(entry, "build_command", context=context)
        generate_command = _optional_command(entry, "generate_command", context=context)
        if generate_command is None:
            raise ValueError(f"{context}: standalone test blueprints must declare `generate_command`")
        validation = entry.get("validation") or {}
        if not isinstance(validation, dict):
            raise ValueError(f"{context}: expected object field `validation`")
        panel_regression_script = _optional_string(validation, "panel_regression_script", context=context)
        browser_tests_path = _optional_string(validation, "browser_tests_path", context=context)
        fixtures.append(
            StandaloneTestBlueprint(
                slug=slug,
                title=title,
                category=category,
                summary=summary,
                tags=tags,
                project_root=project_root,
                build_command=build_command,
                generate_command=generate_command,
                panel_regression_script=panel_regression_script,
                browser_tests_path=browser_tests_path,
            )
        )
    return categories, fixtures


def load_test_blueprint_categories(manifest_path: Path) -> tuple[str, ...]:
    categories, _ = load_test_blueprint_catalog(manifest_path)
    return categories


def load_test_blueprints_manifest(manifest_path: Path) -> list[StandaloneTestBlueprint]:
    _, fixtures = load_test_blueprint_catalog(manifest_path)
    return fixtures


def find_test_blueprint(fixtures: list[StandaloneTestBlueprint], slug: str) -> StandaloneTestBlueprint:
    for fixture in fixtures:
        if fixture.slug == slug:
            return fixture
    known = ", ".join(sorted(f.slug for f in fixtures))
    raise SystemExit(f"[blueprint-test-blueprints] unknown fixture `{slug}`; known fixtures: {known}")


def format_project_command(command: tuple[str, ...], *, package_root: Path, project_dir: Path, output_dir: Path, slug: str) -> list[str]:
    placeholders = {
        "package_root": str(package_root),
        "project_dir": str(project_dir),
        "output_dir": str(output_dir),
        "slug": slug,
    }
    return [part.format(**placeholders) for part in command]


def generate_standalone_test_blueprint(package_root: Path, fixture: StandaloneTestBlueprint, output_dir: Path) -> None:
    project_dir = package_root / fixture.project_root
    if not project_dir.exists():
        raise SystemExit(f"[blueprint-test-blueprints] missing project root for `{fixture.slug}`: {project_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    rebuilt = rebuild_embedded_asset_owners(package_root)
    for target in rebuilt:
        print(f"[blueprint-harness] rebuilt embedded-asset owner target: {target}")
    original_manifest = snapshot_tracked_project_manifest(project_dir)
    rewritten_lakefile, original_lakefile_text = maybe_rewrite_in_repo_blueprint_dependency(project_dir, package_root)
    try:
        run(reference_update_command(package_root, project_dir), cwd=project_dir)
        if fixture.build_command is not None:
            run(
                lean_low_priority_command(
                    package_root,
                    *format_project_command(
                        fixture.build_command,
                        package_root=package_root,
                        project_dir=project_dir,
                        output_dir=output_dir,
                        slug=fixture.slug,
                    ),
                ),
                cwd=project_dir,
            )
        run(
            lean_low_priority_command(
                package_root,
                *format_project_command(
                    fixture.generate_command,
                    package_root=package_root,
                    project_dir=project_dir,
                    output_dir=output_dir,
                    slug=fixture.slug,
                ),
            ),
            cwd=project_dir,
        )
    finally:
        restore_tracked_project_manifest(original_manifest)
        if rewritten_lakefile is not None and original_lakefile_text is not None:
            rewritten_lakefile.write_text(original_lakefile_text, encoding="utf-8")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python3 -m scripts.blueprint_test_blueprints")
    parser.add_argument("--manifest", default=None, help="Path to the standalone test blueprint manifest.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list")
    sub.add_parser("list-json")

    gen = sub.add_parser("generate")
    gen.add_argument("slug")
    gen.add_argument("output_dir")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_test_blueprint_manifest(args.manifest, layout.package_root)
    fixtures = load_test_blueprints_manifest(manifest_path)

    if args.cmd == "list":
        for fixture in fixtures:
            print(fixture.slug)
        return 0
    if args.cmd == "list-json":
        print(json.dumps([fixture.meta for fixture in fixtures], separators=(",", ":")))
        return 0
    if args.cmd == "generate":
        fixture = find_test_blueprint(fixtures, args.slug)
        generate_standalone_test_blueprint(layout.package_root, fixture, Path(args.output_dir).resolve())
        return 0
    raise SystemExit("unreachable")


if __name__ == "__main__":
    raise SystemExit(main())

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import shutil
import subprocess

from scripts.blueprint_harness_manifest import (
    load_json_object,
    optional_command as _optional_command,
    optional_string as _optional_string,
    optional_string_list as _optional_string_list,
    require_string as _require_string,
    require_string_list as _require_string_list,
    resolve_manifest_path,
)
from scripts.blueprint_harness_paths import detect_harness_layout
from scripts.blueprint_harness_project_commands import (
    format_project_command,
    maybe_in_repo_blueprint_dependency_override,
    rebuild_and_log_embedded_asset_owners,
    restore_tracked_project_manifest,
    run_project_lake_update,
    run_project_update_build_generate,
    snapshot_tracked_project_manifest,
)
from scripts.blueprint_harness_utils import (
    StepFailure,
    format_command,
    lean_low_priority_command,
    print_failure_summary,
    run,
)
from scripts.blueprint_harness_validation import SiteValidationCheck, run_site_validation_checks


TAG_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
TEST_BLUEPRINT_HARNESS_PREFIX = "[blueprint-test-blueprints]"
TEST_BLUEPRINT_INDEX_CSS = """:root { color-scheme: light; --bg: #f8fafc; --panel: #ffffff; --text: #0f172a; --muted: #475569; --border: #cbd5e1; --accent: #0f766e; }
* { box-sizing: border-box; }
body { margin: 0; font-family: ui-sans-serif, system-ui, sans-serif; background: linear-gradient(180deg, #f8fafc, #eef2ff 45%, #f8fafc); color: var(--text); }
main { width: min(70rem, calc(100% - 2rem)); margin: 0 auto; padding: 2rem 0 3rem; }
header { margin-bottom: 1.5rem; }
h1 { margin: 0 0 0.5rem; font-size: clamp(2rem, 4vw, 2.75rem); }
.lede { margin: 0; max-width: 54rem; color: var(--muted); line-height: 1.5; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(18rem, 1fr)); gap: 1rem; }
.chip_row { display: flex; flex-wrap: wrap; gap: 0.55rem; margin: 1.1rem 0 1.6rem; }
.chip { display: inline-flex; align-items: center; border: 1px solid var(--border); border-radius: 999px; background: var(--panel); padding: 0.35rem 0.7rem; font-size: 0.92rem; font-weight: 600; box-shadow: 0 6px 18px rgba(15, 23, 42, 0.05); }
.category_section + .category_section { margin-top: 1.8rem; }
.category_header { display: flex; flex-wrap: wrap; align-items: baseline; justify-content: space-between; gap: 0.5rem 1rem; margin-bottom: 0.9rem; }
.category_header h2 { margin: 0; font-size: 1.2rem; }
.category_header p { margin: 0; color: var(--muted); font-size: 0.92rem; }
.card { border: 1px solid var(--border); border-radius: 1rem; background: var(--panel); padding: 1rem 1.05rem; box-shadow: 0 10px 30px rgba(15, 23, 42, 0.06); }
.card h2 { margin: 0 0 0.4rem; font-size: 1.05rem; }
.category { margin: 0.25rem 0 0; color: var(--accent); font-size: 0.78rem; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; }
.kind { margin: 0.2rem 0 0; color: var(--muted); font-size: 0.78rem; font-style: italic; }
.card p { margin: 0.45rem 0 0; line-height: 1.45; }
.slug { color: var(--muted); font-size: 0.9rem; }
.tag_list { list-style: none; padding: 0; margin: 0.65rem 0 0; display: flex; flex-wrap: wrap; gap: 0.45rem; }
.tag_list li { border: 1px solid #d8dee9; border-radius: 999px; background: #f8fafc; color: var(--muted); padding: 0.2rem 0.55rem; font-size: 0.78rem; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }"""


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
    def meta(self) -> dict[str, object]:
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
    return resolve_manifest_path(path_text, default_test_blueprint_manifest(package_root))


def _optional_tags(data: dict, key: str, *, context: str) -> tuple[str, ...]:
    tags = _optional_string_list(data, key, context=context, unique=True) or ()
    invalid = [tag for tag in tags if not TAG_PATTERN.fullmatch(tag)]
    if invalid:
        raise ValueError(f"{context}: invalid tag values in `{key}`: {', '.join(invalid)}")
    return tags


def load_test_blueprint_catalog(manifest_path: Path) -> tuple[tuple[str, ...], list[StandaloneTestBlueprint]]:
    raw = load_json_object(manifest_path)
    if raw.get("version") != 1:
        raise ValueError(f"{manifest_path}: unsupported manifest version {raw.get('version')!r}")

    categories = _require_string_list(raw, "categories", context=str(manifest_path), unique=True)

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


def list_curated_test_doc_slugs(package_root: Path) -> list[str]:
    result = subprocess.run(
        lean_low_priority_command(package_root, "lake", "exe", "blueprint-test-docs", "--list"),
        cwd=package_root,
        check=True,
        text=True,
        capture_output=True,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def list_curated_test_doc_meta(package_root: Path) -> list[dict[str, object]]:
    result = subprocess.run(
        lean_low_priority_command(package_root, "lake", "exe", "blueprint-test-docs", "--list-json"),
        cwd=package_root,
        check=True,
        text=True,
        capture_output=True,
    )
    data = json.loads(result.stdout)
    if not isinstance(data, list):
        raise ValueError("expected `blueprint-test-docs --list-json` to emit a JSON list")
    return [entry for entry in data if isinstance(entry, dict)]


def test_blueprint_index_entries(
    package_root: Path,
    fixtures: list[StandaloneTestBlueprint],
    selected_slugs: list[str],
) -> list[dict[str, object]]:
    meta_by_slug = {
        str(entry["slug"]): entry
        for entry in list_curated_test_doc_meta(package_root)
        if isinstance(entry.get("slug"), str)
    }
    for fixture in fixtures:
        meta_by_slug[fixture.slug] = fixture.meta
    return [meta_by_slug[slug] for slug in selected_slugs if slug in meta_by_slug]


def render_test_blueprint_tag_list(tags: object) -> str:
    if not tags:
        return ""
    tag_chips = "".join(f"<li>{tag}</li>" for tag in tags)
    return f'<ul class="tag_list">{tag_chips}</ul>'


def render_test_blueprint_card(entry: dict[str, object]) -> str:
    category = str(entry.get("category", "Uncategorized"))
    slug = str(entry["slug"])
    title = str(entry["title"])
    summary = str(entry["summary"])
    kind = str(entry.get("kind", "curated_doc")).replace("_", " ")
    tags_html = render_test_blueprint_tag_list(entry.get("tags", []))
    return f"""
        <article class="card">
          <h2><a href="./{slug}/html-multi/">{title}</a></h2>
          <p class="category">{category}</p>
          <p class="kind">{kind}</p>
          <p class="slug"><code>{slug}</code></p>
          <p>{summary}</p>
          {tags_html}
          <p><a href="./{slug}/html-multi/">Open site</a></p>
        </article>
        """


def category_anchor(category: str) -> str:
    return category.lower().replace(" ", "-")


def group_test_blueprint_cards(
    category_order: tuple[str, ...],
    entries: list[dict[str, object]],
) -> dict[str, list[str]]:
    cards_by_category = {category: [] for category in category_order}
    for entry in entries:
        category = str(entry.get("category", "Uncategorized"))
        cards_by_category.setdefault(category, []).append(render_test_blueprint_card(entry))
    return cards_by_category


def render_test_blueprint_nav(categories: list[str]) -> str:
    return "".join(
        f'<a class="chip" href="#{category_anchor(category)}">{category}</a>'
        for category in categories
    )


def render_test_blueprint_category_section(category: str, cards: list[str]) -> str:
    site_count = f"{len(cards)} site{'s' if len(cards) != 1 else ''}"
    return f"""
        <section class="category_section" id="{category_anchor(category)}">
          <div class="category_header">
            <h2>{category}</h2>
            <p>{site_count}</p>
          </div>
          <div class="grid">
            {''.join(cards)}
          </div>
        </section>
        """


def render_test_blueprint_index_html(category_order: tuple[str, ...], entries: list[dict[str, object]]) -> str:
    cards_by_category = group_test_blueprint_cards(category_order, entries)
    visible_categories = [category for category in category_order if cards_by_category.get(category)]
    sections_html = "".join(
        render_test_blueprint_category_section(category, cards_by_category[category])
        for category in visible_categories
    )
    return f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Test Blueprint Artifacts</title>
    <style>
{TEST_BLUEPRINT_INDEX_CSS}
    </style>
  </head>
  <body>
    <main>
      <header>
        <h1>Test Blueprint Artifacts</h1>
        <p class="lede">Generated inspection sites for local HTML-producing test fixtures. The catalog mixes curated doc-backed fixtures with standalone test packages such as <code>preview_runtime_showcase</code>, grouped here so browser, graph, summary, and metadata cases are easier to browse together.</p>
        <p class="lede">Each site declares one primary category plus optional tags for cross-cutting coverage.</p>
      </header>
      <nav class="chip_row">
        {render_test_blueprint_nav(visible_categories)}
      </nav>
      {sections_html}
    </main>
  </body>
</html>
"""


def write_test_blueprint_index(output_root: Path, category_order: tuple[str, ...], entries: list[dict[str, object]]) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "index.html").write_text(
        render_test_blueprint_index_html(category_order, entries),
        encoding="utf-8",
    )


def split_generation_targets(
    package_root: Path,
    fixtures: list[StandaloneTestBlueprint],
    requested_slugs: list[str],
) -> tuple[list[str], list[StandaloneTestBlueprint]]:
    if not requested_slugs:
        return list_curated_test_doc_slugs(package_root), fixtures

    fixture_by_slug = {fixture.slug: fixture for fixture in fixtures}
    doc_slugs: list[str] = []
    standalone_fixtures: list[StandaloneTestBlueprint] = []
    for target in requested_slugs:
        fixture = fixture_by_slug.get(target)
        if fixture is None:
            doc_slugs.append(target)
        else:
            standalone_fixtures.append(fixture)
    return doc_slugs, standalone_fixtures


def prune_stale_test_blueprint_outputs(output_root: Path, expected_slugs: set[str]) -> None:
    if not output_root.exists():
        return
    for child in output_root.iterdir():
        if child.is_dir() and child.name not in expected_slugs:
            shutil.rmtree(child)


def generate_curated_test_doc(package_root: Path, slug: str, output_dir: Path) -> None:
    run(
        lean_low_priority_command(
            package_root,
            "lake",
            "exe",
            "blueprint-test-docs",
            slug,
            "--output",
            str(output_dir),
        ),
        cwd=package_root,
    )


def generate_test_blueprint_outputs(
    package_root: Path,
    category_order: tuple[str, ...],
    fixtures: list[StandaloneTestBlueprint],
    output_root: Path,
    requested_slugs: list[str],
) -> None:
    doc_slugs, standalone_fixtures = split_generation_targets(package_root, fixtures, requested_slugs)
    standalone_slugs = [fixture.slug for fixture in standalone_fixtures]

    if not requested_slugs:
        prune_stale_test_blueprint_outputs(output_root, {*doc_slugs, *standalone_slugs})

    for slug in doc_slugs:
        generate_curated_test_doc(package_root, slug, output_root / slug)

    for fixture in standalone_fixtures:
        generate_standalone_test_blueprint(package_root, fixture, output_root / fixture.slug)

    selected_slugs = [*doc_slugs, *standalone_slugs]
    write_test_blueprint_index(
        output_root,
        category_order,
        test_blueprint_index_entries(package_root, fixtures, selected_slugs),
    )


def test_blueprint_site_dir(output_root: Path, fixture: StandaloneTestBlueprint) -> Path:
    return output_root / fixture.slug / "html-multi"


def _subprocess_failure(step: str, err: subprocess.CalledProcessError) -> StepFailure:
    command = err.cmd
    if isinstance(command, (list, tuple)):
        detail_command = format_command([str(part) for part in command])
    else:
        detail_command = str(command)
    return StepFailure(step=step, detail=f"exit code {err.returncode}: {detail_command}")


def validate_test_blueprint_outputs(
    package_root: Path,
    category_order: tuple[str, ...],
    fixtures: list[StandaloneTestBlueprint],
    output_root: Path,
    pytest_args: list[str],
    *,
    skip_generate: bool = False,
    skip_panel_regression: bool = False,
    skip_browser_tests: bool = False,
    run_real_pdf_smoke: bool = False,
    stop_on_first_failure: bool = False,
) -> int:
    failures: list[StepFailure] = []

    if not skip_generate:
        try:
            generate_test_blueprint_outputs(package_root, category_order, fixtures, output_root, [])
        except subprocess.CalledProcessError as err:
            failures.append(_subprocess_failure("generate test blueprints", err))
            return print_failure_summary(failures, prefix=TEST_BLUEPRINT_HARNESS_PREFIX)
        except SystemExit as err:
            failures.append(StepFailure("generate test blueprints", str(err)))
            return print_failure_summary(failures, prefix=TEST_BLUEPRINT_HARNESS_PREFIX)

    failures.extend(
        run_site_validation_checks(
            package_root,
            [
                SiteValidationCheck(
                    label=fixture.slug,
                    site_dir=test_blueprint_site_dir(output_root, fixture),
                    panel_regression_script=fixture.panel_regression_script,
                    browser_tests_path=fixture.browser_tests_path,
                )
                for fixture in fixtures
            ],
            pytest_args,
            skip_panel_regression=skip_panel_regression,
            skip_browser_tests=skip_browser_tests,
            stop_on_first_failure=stop_on_first_failure,
        )
    )

    if run_real_pdf_smoke and not (stop_on_first_failure and failures):
        if failure := run_real_pdf_smoke_check(package_root, output_root):
            failures.append(failure)

    return print_failure_summary(failures, prefix=TEST_BLUEPRINT_HARNESS_PREFIX)


def run_real_pdf_smoke_check(package_root: Path, output_root: Path) -> StepFailure | None:
    if shutil.which("lualatex") is None:
        print(f"{TEST_BLUEPRINT_HARNESS_PREFIX} real PDF smoke skipped: lualatex not found")
        return None

    project_dir = package_root / "project_template"
    output_dir = output_root / "_real-pdf-smoke"
    original_manifest = snapshot_tracked_project_manifest(project_dir)
    try:
        with maybe_in_repo_blueprint_dependency_override(project_dir, package_root, log=True):
            run_project_update_build_generate(
                package_root,
                project_dir,
                update_project=lambda: run_project_lake_update(package_root, project_dir),
                build_command=("lake", "build", "ProjectTemplate"),
                generate_command=(
                    "lake",
                    "exe",
                    "vbp",
                    "build",
                    "--output",
                    "{output_dir}",
                    "--pdf",
                ),
                format_command=lambda command: format_project_command(
                    command,
                    {
                        "package_root": package_root,
                        "project_dir": project_dir,
                        "output_dir": output_dir,
                        "slug": "_real-pdf-smoke",
                    },
                ),
                skip_build=False,
                project_id="real-pdf-smoke",
            )
    except subprocess.CalledProcessError as err:
        return _subprocess_failure("real PDF smoke", err)
    except SystemExit as err:
        return StepFailure("real PDF smoke", str(err))
    finally:
        restore_tracked_project_manifest(original_manifest)

    pdf_path = output_dir / "pdf" / "main.pdf"
    if not pdf_path.exists():
        return StepFailure("real PDF smoke", f"missing expected PDF: {pdf_path}")
    if pdf_path.stat().st_size == 0:
        return StepFailure("real PDF smoke", f"empty PDF: {pdf_path}")
    print(f"{TEST_BLUEPRINT_HARNESS_PREFIX} real PDF smoke wrote {pdf_path}")
    return None


def find_test_blueprint(fixtures: list[StandaloneTestBlueprint], slug: str) -> StandaloneTestBlueprint:
    for fixture in fixtures:
        if fixture.slug == slug:
            return fixture
    known = ", ".join(sorted(f.slug for f in fixtures))
    raise SystemExit(f"[blueprint-test-blueprints] unknown fixture `{slug}`; known fixtures: {known}")


def generate_standalone_test_blueprint(package_root: Path, fixture: StandaloneTestBlueprint, output_dir: Path) -> None:
    project_dir = package_root / fixture.project_root
    if not project_dir.exists():
        raise SystemExit(f"[blueprint-test-blueprints] missing project root for `{fixture.slug}`: {project_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    rebuild_and_log_embedded_asset_owners(package_root)
    original_manifest = snapshot_tracked_project_manifest(project_dir)
    try:
        with maybe_in_repo_blueprint_dependency_override(project_dir, package_root):
            run_project_update_build_generate(
                package_root,
                project_dir,
                update_project=lambda: run_project_lake_update(package_root, project_dir),
                build_command=fixture.build_command,
                generate_command=fixture.generate_command,
                format_command=lambda command: format_project_command(
                    command,
                    {
                        "package_root": package_root,
                        "project_dir": project_dir,
                        "output_dir": output_dir,
                        "slug": fixture.slug,
                    },
                ),
                skip_build=False,
                project_id=fixture.slug,
            )
    finally:
        restore_tracked_project_manifest(original_manifest)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python3 -m scripts.blueprint_test_blueprints")
    parser.add_argument("--manifest", default=None, help="Path to the standalone test blueprint manifest.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list")
    sub.add_parser("list-json")

    gen = sub.add_parser("generate")
    gen.add_argument("slug")
    gen.add_argument("output_dir")

    gen_all = sub.add_parser("generate-all")
    gen_all.add_argument(
        "--output-root",
        default=None,
        help="Output root. Defaults to the current checkout's worktree-aware `_out/.../test-blueprints` root.",
    )
    gen_all.add_argument("slug", nargs="*", help="Optional curated doc or standalone fixture slug to generate.")

    validate = sub.add_parser(
        "validate",
        help="Generate test blueprints and run configured regressions.",
        description=(
            "Generate the in-repo test blueprint outputs, then run any configured standalone panel checks "
            "and browser regression suites. Use --pytest-arg or pass extra unknown arguments to forward "
            "pytest filters and options."
        ),
    )
    validate.add_argument(
        "--output-root",
        default=None,
        help="Output root. Defaults to the current checkout's worktree-aware `_out/.../test-blueprints` root.",
    )
    validate.add_argument(
        "--skip-generate",
        action="store_true",
        help="Skip artifact generation and validate existing test-blueprint output.",
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
    validate.add_argument(
        "--run-real-pdf-smoke",
        action="store_true",
        help="If lualatex is available, build project_template with --pdf and check pdf/main.pdf.",
    )
    validate.add_argument(
        "--pytest-arg",
        action="append",
        default=[],
        help="Extra argument forwarded to pytest. Repeat for multiple arguments.",
    )
    validate.add_argument(
        "--stop-on-first-failure",
        action="store_true",
        help="Stop validation as soon as one phase fails instead of collecting later failures.",
    )
    return parser


def _pytest_passthrough_args(args: list[str]) -> list[str]:
    if args and args[0] == "--":
        return args[1:]
    return args


def _combined_pytest_args(args: argparse.Namespace, passthrough_args: list[str]) -> list[str]:
    return [*args.pytest_arg, *_pytest_passthrough_args(passthrough_args)]


def main() -> int:
    parser = build_parser()
    args, unknown_args = parser.parse_known_args()
    if args.cmd != "validate" and unknown_args:
        parser.error(f"unrecognized arguments: {' '.join(unknown_args)}")
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_test_blueprint_manifest(args.manifest, layout.package_root)
    category_order, fixtures = load_test_blueprint_catalog(manifest_path)

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
    if args.cmd == "generate-all":
        output_root = Path(args.output_root).resolve() if args.output_root else layout.test_blueprint_output_root
        generate_test_blueprint_outputs(layout.package_root, category_order, fixtures, output_root, args.slug)
        return 0
    if args.cmd == "validate":
        output_root = Path(args.output_root).resolve() if args.output_root else layout.test_blueprint_output_root
        return validate_test_blueprint_outputs(
            layout.package_root,
            category_order,
            fixtures,
            output_root,
            _combined_pytest_args(args, unknown_args),
            skip_generate=args.skip_generate,
            skip_panel_regression=args.skip_panel_regression,
            skip_browser_tests=args.skip_browser_tests,
            run_real_pdf_smoke=args.run_real_pdf_smoke,
            stop_on_first_failure=args.stop_on_first_failure,
        )
    raise SystemExit("unreachable")


if __name__ == "__main__":
    raise SystemExit(main())

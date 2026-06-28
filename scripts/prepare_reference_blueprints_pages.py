#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
from pathlib import Path
import shutil


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare a GitHub Pages site for generated reference blueprints, "
            "test blueprints, and optional JavaScript API docs."
        )
    )
    parser.add_argument(
        "--reference-root",
        default="_out/reference-blueprints",
        help="Directory containing generated reference blueprint outputs.",
    )
    parser.add_argument(
        "--test-root",
        default="_out/test-blueprints",
        help="Directory containing generated test blueprint outputs.",
    )
    parser.add_argument(
        "--output-root",
        default="_site",
        help="Directory to populate with the Pages artifact.",
    )
    parser.add_argument(
        "--js-api-docs-root",
        default=None,
        help="Optional generated JSDoc directory to publish under js-api/.",
    )
    return parser.parse_args()


def html_link(project_id: str, *, release: str | None = None, prefix: str = "reference-blueprints/") -> str:
    label = html.escape(project_id)
    if release is None:
        href = f"{prefix}{label}/"
    else:
        href = f"{prefix}{html.escape(release)}/{label}/"
    return f'<li><a href="{href}">{label}</a></li>'


def html_test_link(slug: str) -> str:
    label = html.escape(slug)
    href = f"test-blueprints/{label}/html-multi/"
    return f'<li><a href="{href}">{label}</a></li>'


def html_release_link(release: str, *, prefix: str = "reference-blueprints/") -> str:
    label = html.escape(release)
    href = f"{prefix}{label}/"
    return f'<li><a href="{href}">{label}</a></li>'


def write_reference_index(reference_root: Path, release_projects: dict[str | None, list[str]]) -> None:
    if None in release_projects:
        items = [html_link(project_id, prefix="") for project_id in release_projects[None]]
        body = [
            "<!doctype html>",
            "<html lang=\"en\">",
            "<meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "<title>Reference Blueprints</title>",
            "<body>",
            "<h1>Reference Blueprints</h1>",
            "<ul>",
            *items,
            "</ul>",
            "</body>",
            "</html>",
        ]
        (reference_root / "index.html").write_text("\n".join(body) + "\n", encoding="utf-8")
        return

    for release, projects in release_projects.items():
        assert release is not None
        release_root = reference_root / release
        release_root.mkdir(parents=True, exist_ok=True)
        body = [
            "<!doctype html>",
            "<html lang=\"en\">",
            "<meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            f"<title>Reference Blueprints {html.escape(release)}</title>",
            "<body>",
            f"<h1>Reference Blueprints {html.escape(release)}</h1>",
            "<ul>",
            *[html_link(project_id, prefix="") for project_id in projects],
            "</ul>",
            "</body>",
            "</html>",
        ]
        (release_root / "index.html").write_text("\n".join(body) + "\n", encoding="utf-8")

    body = [
        "<!doctype html>",
        "<html lang=\"en\">",
        "<meta charset=\"utf-8\">",
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
        "<title>Reference Blueprint Releases</title>",
        "<body>",
        "<h1>Reference Blueprint Releases</h1>",
        "<ul>",
        *[html_release_link(release, prefix="") for release in sorted(release_projects)],
        "</ul>",
        "</body>",
        "</html>",
    ]
    (reference_root / "index.html").write_text("\n".join(body) + "\n", encoding="utf-8")


def write_redirect_alias(alias_root: Path, target_href: str, *, label: str) -> None:
    alias_root.mkdir(parents=True, exist_ok=True)
    escaped_target = html.escape(target_href, quote=True)
    escaped_label = html.escape(label)
    body = [
        "<!doctype html>",
        "<html lang=\"en\">",
        "<meta charset=\"utf-8\">",
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
        f"<meta http-equiv=\"refresh\" content=\"0; url={escaped_target}\">",
        f"<link rel=\"canonical\" href=\"{escaped_target}\">",
        f"<title>{escaped_label}</title>",
        "<body>",
        f"<p><a href=\"{escaped_target}\">Open {escaped_label}</a></p>",
        "</body>",
        "</html>",
    ]
    (alias_root / "index.html").write_text("\n".join(body) + "\n", encoding="utf-8")


def write_unique_project_aliases(reference_root: Path, release_projects: dict[str | None, list[str]]) -> None:
    if None in release_projects:
        return

    releases_by_project: dict[str, list[str]] = {}
    for release, projects in release_projects.items():
        assert release is not None
        for project in projects:
            releases_by_project.setdefault(project, []).append(release)

    for project, releases in releases_by_project.items():
        if len(releases) != 1:
            continue
        alias_root = reference_root / project
        if alias_root.exists():
            continue
        release = releases[0]
        write_redirect_alias(
            alias_root,
            f"../{release}/{project}/",
            label=project,
        )


def copy_reference_sites(reference_root: Path, publish_reference_root: Path) -> dict[str | None, list[str]]:
    release_projects: dict[str | None, list[str]] = {}
    children = sorted(path for path in reference_root.iterdir() if path.is_dir())
    if all((child / "html-multi").exists() for child in children):
        projects: list[str] = []
        for project_dir in children:
            shutil.copytree(project_dir / "html-multi", publish_reference_root / project_dir.name)
            projects.append(project_dir.name)
        release_projects[None] = projects
        return release_projects

    for release_dir in children:
        projects: list[str] = []
        for project_dir in sorted(path for path in release_dir.iterdir() if path.is_dir()):
            site_dir = project_dir / "html-multi"
            if not site_dir.exists():
                continue
            shutil.copytree(site_dir, publish_reference_root / release_dir.name / project_dir.name)
            projects.append(project_dir.name)
        if projects:
            release_projects[release_dir.name] = projects
    return release_projects


def copy_js_api_docs(js_api_docs_root: Path, publish_js_api_root: Path) -> None:
    if not js_api_docs_root.exists():
        raise SystemExit(f"missing JavaScript API docs root: {js_api_docs_root}")
    if not js_api_docs_root.is_dir():
        raise SystemExit(f"JavaScript API docs root is not a directory: {js_api_docs_root}")
    if not (js_api_docs_root / "index.html").exists():
        raise SystemExit(f"JavaScript API docs root is missing index.html: {js_api_docs_root}")
    shutil.copytree(js_api_docs_root, publish_js_api_root)


def main() -> int:
    args = parse_args()
    reference_root = Path(args.reference_root).resolve()
    test_root = Path(args.test_root).resolve()
    output_root = Path(args.output_root).resolve()
    publish_reference_root = output_root / "reference-blueprints"
    publish_test_root = output_root / "test-blueprints"

    if not reference_root.exists():
        raise SystemExit(f"missing reference blueprint output root: {reference_root}")
    if not test_root.exists():
        raise SystemExit(f"missing test blueprint output root: {test_root}")

    if output_root.exists():
        shutil.rmtree(output_root)
    publish_reference_root.mkdir(parents=True, exist_ok=True)
    publish_test_root.mkdir(parents=True, exist_ok=True)

    release_projects = copy_reference_sites(reference_root, publish_reference_root)
    write_reference_index(publish_reference_root, release_projects)
    write_unique_project_aliases(publish_reference_root, release_projects)

    publish_js_api_docs = args.js_api_docs_root is not None
    if publish_js_api_docs:
        copy_js_api_docs(Path(args.js_api_docs_root).resolve(), output_root / "js-api")

    test_blueprints: list[str] = []
    for test_dir in sorted(path for path in test_root.iterdir() if path.is_dir()):
        if not (test_dir / "html-multi").exists():
            continue
        shutil.copytree(test_dir, publish_test_root / test_dir.name)
        test_blueprints.append(test_dir.name)
    test_index = test_root / "index.html"
    if test_index.exists():
        shutil.copy2(test_index, publish_test_root / "index.html")

    index = output_root / "index.html"
    index.write_text(
        "\n".join(
            [
                "<!doctype html>",
                "<html lang=\"en\">",
                "<meta charset=\"utf-8\">",
                "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
                "<title>Verso Blueprint Rendered Artifacts</title>",
                "<body>",
                "<h1>Verso Blueprint Rendered Artifacts</h1>",
                (
                    "<p>Generated reference sites, test sites, and JavaScript API docs "
                    "assembled from the current workflow run.</p>"
                    if publish_js_api_docs
                    else "<p>Generated reference and test sites assembled from the current workflow run.</p>"
                ),
                "<h2>Reference Blueprints</h2>",
                "<p><a href=\"reference-blueprints/\">Open reference blueprint index</a></p>",
                *(
                    [
                        "<ul>",
                        *[html_link(project_id) for project_id in release_projects[None]],
                        "</ul>",
                    ]
                    if None in release_projects
                    else [
                        "<ul>",
                        *[
                            html_release_link(release)
                            for release in sorted(release_projects)
                        ],
                        "</ul>",
                    ]
                ),
                *(
                    [
                        "<h2>JavaScript API</h2>",
                        "<p><a href=\"js-api/\">Open JavaScript API documentation</a></p>",
                    ]
                    if publish_js_api_docs
                    else []
                ),
                "<h2>Test Blueprints</h2>",
                "<p><a href=\"test-blueprints/\">Open categorized test blueprint index</a></p>",
                "<ul>",
                *[html_test_link(slug) for slug in test_blueprints],
                "</ul>",
                "</body>",
                "</html>",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

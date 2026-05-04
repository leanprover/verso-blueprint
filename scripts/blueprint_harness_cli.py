from __future__ import annotations

import argparse


def add_output_root_argument(command_parser: argparse.ArgumentParser) -> None:
    command_parser.add_argument(
        "output_root",
        nargs="?",
        default=None,
        help="Artifact output root. Defaults to the current checkout's harness output root.",
    )
    command_parser.add_argument(
        "--output-root",
        dest="output_root_option",
        metavar="OUTPUT_ROOT",
        default=None,
        help="Artifact output root. Overrides the positional output_root argument.",
    )


def selected_output_root(args: argparse.Namespace) -> str | None:
    return getattr(args, "output_root_option", None) or getattr(args, "output_root", None)


def add_project_selection_argument(
    command_parser: argparse.ArgumentParser,
    *,
    help_text: str,
    include_example_alias: bool = True,
) -> None:
    command_parser.add_argument(
        "--project",
        *(("--example",) if include_example_alias else ()),
        dest="project",
        action="append",
        help=help_text,
    )


def add_manifest_argument(command_parser: argparse.ArgumentParser) -> None:
    command_parser.add_argument(
        "--manifest",
        default=None,
        help="Path to the project manifest. Defaults to tests/harness/projects.json.",
    )


def add_serial_argument(command_parser: argparse.ArgumentParser) -> None:
    command_parser.add_argument(
        "--serial",
        action="store_true",
        help="Render selected projects serially instead of in parallel where supported.",
    )


def add_allow_local_build_argument(command_parser: argparse.ArgumentParser, *, help_text: str) -> None:
    command_parser.add_argument(
        "--allow-local-build",
        action="store_true",
        help=help_text,
    )


def add_allow_unsafe_root_main_argument(command_parser: argparse.ArgumentParser) -> None:
    command_parser.add_argument(
        "--allow-unsafe-root-release",
        "--allow-unsafe-root-main",
        dest="allow_unsafe_root_release",
        action="store_true",
        help="Allow this command to run from the root checkout even when the active release branch is dirty or out of sync.",
    )


def add_optional_worktree_name_argument(command_parser: argparse.ArgumentParser) -> None:
    command_parser.add_argument("name", nargs="?", default=None, help="Worktree name. Defaults to the current worktree.")

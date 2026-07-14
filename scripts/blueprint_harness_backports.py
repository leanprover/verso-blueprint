from __future__ import annotations

from collections.abc import Iterable


EXEMPT_FILE_NAMES = frozenset(
    {
        ".gitattributes",
        ".gitignore",
        "branch-policy.json",
        "LICENSE",
    }
)
EXEMPT_PATH_PREFIXES = (".github/", "doc/", "LICENSES/")


def backport_exemption_violations(paths: Iterable[str]) -> tuple[str, ...]:
    """Return changed paths that require release-line backports."""
    violations: list[str] = []
    for raw_path in paths:
        path = raw_path.removeprefix("./")
        exempt = (
            path.endswith(".md")
            or path in EXEMPT_FILE_NAMES
            or path.startswith(EXEMPT_PATH_PREFIXES)
        )
        if not exempt:
            violations.append(path)
    return tuple(violations)

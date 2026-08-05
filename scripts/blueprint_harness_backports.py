from __future__ import annotations

from collections.abc import Iterable


EXEMPT_PATHS = frozenset(
    {
        ".gitattributes",
        ".gitignore",
        "branch-policy.json",
        "LICENSE",
        "tests/harness/projects.json",
    }
)
EXEMPT_PATH_PREFIXES = (".github/", "doc/", "LICENSES/")
RELEASE_LINE_BOOTSTRAP_STATUS = "release-line bootstrap"
RELEASE_LINE_RETIREMENT_STATUS = "release-line retirement"


def backport_exemption_violations(paths: Iterable[str]) -> tuple[str, ...]:
    """Return changed paths that require release-line backports."""
    violations: list[str] = []
    for raw_path in paths:
        path = raw_path.removeprefix("./")
        exempt = (
            path.endswith(".md")
            or path in EXEMPT_PATHS
            or path.startswith(EXEMPT_PATH_PREFIXES)
        )
        if not exempt:
            violations.append(path)
    return tuple(violations)

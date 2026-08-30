from __future__ import annotations

import argparse
from pathlib import Path
import re


MODULE_HEADER = re.compile(r"^module(?:\s*--.*)?\s*$", re.MULTILINE)
ESCAPE_HATCHES = (
    ("backward.privateInPublic", re.compile(r"\bbackward\.privateInPublic\b")),
    ("allowNonModules", re.compile(r"\ballowNonModules\s*:=\s*true\b")),
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Report VBP's Lean module-system conversion status."
    )
    parser.add_argument(
        "--require-all",
        action="store_true",
        help="Fail unless every production Lean source has a module header.",
    )
    args = parser.parse_args()

    package_root = Path(__file__).resolve().parents[1]
    source_files = sorted((package_root / "src").rglob("*.lean"))
    module_files: list[Path] = []
    non_module_files: list[Path] = []
    escape_hatches: list[tuple[str, Path]] = []

    for path in source_files:
        source = path.read_text(encoding="utf-8")
        if MODULE_HEADER.search(source):
            module_files.append(path)
        else:
            non_module_files.append(path)
        for name, pattern in ESCAPE_HATCHES:
            if pattern.search(source):
                escape_hatches.append((name, path))

    lakefile = package_root / "lakefile.lean"
    lakefile_source = lakefile.read_text(encoding="utf-8")
    for name, pattern in ESCAPE_HATCHES:
        if pattern.search(lakefile_source):
            escape_hatches.append((name, lakefile))

    print(f"lean_sources={len(source_files)}")
    print(f"module_sources={len(module_files)}")
    print(f"non_module_sources={len(non_module_files)}")
    print(f"escape_hatches={len(escape_hatches)}")

    for name, path in escape_hatches:
        print(f"error: {name}: {path.relative_to(package_root)}")

    if args.require_all:
        for path in non_module_files:
            print(f"error: missing module header: {path.relative_to(package_root)}")

    return 1 if escape_hatches or (args.require_all and non_module_files) else 0


if __name__ == "__main__":
    raise SystemExit(main())

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "site"
        subprocess.run(
            [
                "./scripts/lean-low-priority",
                "lake",
                "lean",
                "tests/LeanRunExternalMarkupMain.lean",
                "--",
                "--run",
                "tests/LeanRunExternalMarkupMain.lean",
                "--output",
                str(output),
            ],
            cwd=PACKAGE_ROOT,
            check=True,
        )
        cache_path = output / "html-multi" / "-verso-data" / "blueprint-html-cache.json"
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
        html = "\n".join(entry["html"] for entry in cache["entries"])
        expected_fragments = (
            "bp_external_markdown_body",
            "<h1>Markdown witness</h1>",
            "&lt;span&gt;raw HTML stays text&lt;/span&gt;",
        )
        missing = [fragment for fragment in expected_fragments if fragment not in html]
        if missing:
            raise SystemExit(f"missing rendered external-markup fragments: {', '.join(missing)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

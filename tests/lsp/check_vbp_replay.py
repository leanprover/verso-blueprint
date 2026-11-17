"""Exercise saved Rosetta replay from a downstream project's vbp build."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]
MARKER = "Saved Rosetta fixture diagnostic"


def check(project: Path) -> None:
    shutil.copy(REPO / "lean-toolchain", project)
    # Give the consumer its own modules, distinct from VBP's test library.
    (project / "ReplayFixture").mkdir()
    for source in (REPO / "tests/RosettaDocs").glob("*.lean"):
        (project / "ReplayFixture" / source.name).write_text(
            source.read_text().replace("RosettaDocs", "ReplayFixture")
        )
    shutil.copy(REPO / "tests/lsp/BlueprintMain.lean", project)
    (project / "lakefile.toml").write_text(
        'name = "RosettaReplayFixture"\n'
        '[[require]]\nname = "VersoBlueprint"\n'
        f'path = {json.dumps(str(REPO), ensure_ascii=False)}\n'
        '[[lean_lib]]\nname = "ReplayFixture"\n'
    )

    def lake(*args: str, expected: int = 0, error: str = "") -> str:
        command = [str(REPO / "scripts/lean-low-priority"), "lake", *args]
        result = subprocess.run(command, cwd=project, text=True, capture_output=True)
        assert result.returncode == expected and error in result.stderr, (
            command, result.returncode, result.stdout, result.stderr
        )
        return result.stdout

    lake("update", "VersoBlueprint")
    lake("exe", "vbp", "discover")
    bundle_path = "saved analysis.json"
    lake("lean", "BlueprintMain.lean", "--", "--run", "BlueprintMain.lean",
         "fixture-bundle", bundle_path)
    baseline, replay = "baseline", "replay"
    lake("exe", "vbp", "build", "--output", baseline)
    lake("exe", "vbp", "build", "--rosetta-bundle", bundle_path, "--output", replay)
    baseline_site, replay_site = f"{baseline}/html-multi", f"{replay}/html-multi"
    assert MARKER not in (project / baseline_site / "index.html").read_text()
    assert MARKER in (project / replay_site / "index.html").read_text()
    assert MARKER in (project / replay / "tex/main.tex").read_text()
    assert json.loads(lake("exe", "vbp", "check", "--site", replay_site))["ok"]
    for selector in ("labels", "work-queue", "stats"):
        before = lake("exe", "vbp", "query", "--site", baseline_site, selector)
        after = lake("exe", "vbp", "query", "--site", replay_site, selector)
        assert json.loads(before) == json.loads(after), selector

    bundle = json.loads((project / bundle_path).read_text())
    assert len(bundle["requests"]) == 5
    bundle["requests"][0]["request"]["text"] = " " + bundle["requests"][0]["request"]["text"]
    (project / "stale.json").write_text(json.dumps(bundle))
    (project / "invalid.json").write_text("{")
    for path, error in (
        ("stale.json", "analysis request changed"),
        ("absent.json", "Rosetta bundle absent.json"),
        ("invalid.json", "Rosetta bundle invalid.json"),
    ):
        lake("exe", "vbp", "build", "--rosetta-bundle", path, "--output", "rejected",
             expected=1, error=error)
        assert not (project / "rejected").exists()
    lake("exe", "vbp", "build", "--rosetta-bundle", expected=2, error="Missing filename")
    lake("exe", "vbp", "build", "--rosetta-bundle", bundle_path, "--rosetta-bundle", bundle_path,
         expected=2, error="may only be given once")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="vbp-rosetta-replay-") as temp:
        check(Path(temp))
    print("Downstream vbp build replays Rosetta bundles and rejects invalid inputs.")

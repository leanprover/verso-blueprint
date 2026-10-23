"""Run the Lean protocol spike against a mock and explicitly selected servers.

Only this maintainer experiment uses Python; the adapter library imports Lean
and Std and does not depend on this script or the mock server at runtime.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rust-command")
    parser.add_argument("--rocq-command")
    parser.add_argument("--documents", action="store_true",
                        help="Also exercise compiled requests and offline Verso/Blueprint rendering")
    args = parser.parse_args()
    if args.documents and not (args.rust_command and args.rocq_command):
        parser.error("--documents requires both --rust-command and --rocq-command")
    repo = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    prefix = [str(repo / "scripts/lean-low-priority"), "lake", "exe", "verso-lsp-spike"]
    identity = hashlib.sha256()
    for path in sorted([*(repo / "src/VersoLsp").glob("*.lean"),
                        repo / "src/VersoLsp.lean", repo / "src/VersoLspVerso.lean",
                        *(repo / "src/VersoLspVerso").glob("*.lean"),
                        *(repo / "tests/VersoLspDocs").glob("*.lean"),
                        repo / "tests/VersoLspDocsMain.lean",
                        repo / "tests/VersoLspSpike.lean",
                        repo / "lakefile.lean", repo / "lean-toolchain", repo / "lake-manifest.json",
                        *Path(__file__).parent.rglob("*")]):
        if path.is_file() and "__pycache__" not in path.parts:
            identity.update(str(path.relative_to(repo)).encode())
            identity.update(path.read_bytes())
            saved = output / "source" / path.relative_to(repo)
            saved.parent.mkdir(parents=True, exist_ok=True)
            saved.write_bytes(path.read_bytes())
    metadata = {"sourceSha256": identity.hexdigest(),
                "leanToolchain": (repo / "lean-toolchain").read_text().strip(),
                "servers": {}}
    (output / "identity.json").write_text(json.dumps(metadata, indent=2) + "\n")
    cases = [("mock", ["mock", str(repo / "tests/lsp/mock_server.py")])]
    for language, command in (("rust", args.rust_command), ("rocq", args.rocq_command)):
        if command:
            project = output / "projects" / language
            shutil.copytree(repo / "tests/lsp/projects" / language, project, dirs_exist_ok=True)
            version = subprocess.run([command, "--version"], capture_output=True, text=True,
                                     check=True, timeout=15).stdout.strip()
            metadata["servers"][language] = {"command": command, "version": version}
            cases.append((language, ["probe", language, command, str(project)]))
    (output / "identity.json").write_text(json.dumps(metadata, indent=2) + "\n")
    failed = []
    for name, case in cases:
        result = subprocess.run(prefix + case, cwd=repo, capture_output=True,
                                text=True, timeout=120)
        (output / f"{name}.jsonl").write_text(result.stdout)
        (output / f"{name}.stderr").write_text(result.stderr)
        print(f"{name}: {'passed' if result.returncode == 0 else 'FAILED'}", flush=True)
        if result.returncode:
            failed.append(name)
            print(result.stderr[-4000:], flush=True)
    if failed:
        raise SystemExit("failed cases: " + ", ".join(failed))
    if args.documents:
        docs = output / "documents"
        docs.mkdir(exist_ok=True)
        command = prefix[:-1] + ["verso-lsp-docs"]

        def run_document_case(name, arguments, tool=command, cwd=repo):
            result = subprocess.run(tool + arguments, cwd=cwd, capture_output=True,
                                    text=True, timeout=120)
            (docs / f"{name}.stdout").write_text(result.stdout)
            (docs / f"{name}.stderr").write_text(result.stderr)
            if result.returncode:
                raise SystemExit(f"{name} failed:\n{result.stderr[-4000:]}")
            print(f"{name}: passed", flush=True)

        independent = docs / "independent-core"
        independent.mkdir(exist_ok=True)
        (independent / "lean-toolchain").write_text((repo / "lean-toolchain").read_text())
        (independent / "lakefile.toml").write_text(
            'name = "verso_lsp_independence"\n[[lean_lib]]\nname = "VersoLsp"\nsrcDir = '
            + json.dumps(str(repo / "src")) + "\n")
        run_document_case("independent-core", ["VersoLsp"],
                          tool=prefix[:2] + ["build"], cwd=independent)
        assert json.loads((independent / "lake-manifest.json").read_text())["packages"] == []
        run_document_case("plan", ["plan", str(docs / "plan.json")])
        plan = json.loads((docs / "plan.json").read_text())
        assert len(plan) == 5
        for request in plan:
            for text, origin in zip(request["text"].split("\n"), request["origins"], strict=True):
                from urllib.parse import unquote, urlparse
                source = Path(unquote(urlparse(origin["uri"]).path)).read_text().splitlines()
                # A final empty line denotes the insertion point before the fence.
                if text:
                    row = source[origin["line"]].encode("utf-16-le")
                    start = origin["character"] * 2
                    assert row[start:start + len(text.encode("utf-16-le"))].decode("utf-16-le") == text
        run_document_case("analyze", ["analyze", str(docs / "bundle.json"),
                          str(docs / "runtime"), args.rust_command, args.rocq_command])
        run_document_case("snapshot-check", ["check", str(docs / "bundle.json")])
        run_document_case("baseline", ["baseline", str(docs / "baseline")])
        for kind in ("plain", "blueprint"):
            run_document_case(f"offline-{kind}", ["render", str(docs / "bundle.json"),
                              str(docs / kind), kind])
            assert (docs / kind / "html-single/index.html").exists()
            tex = (docs / kind / "tex/main.tex").read_text()
            assert all(text in tex for text in ("pub fn step", "Definition step", "missing", "compiler checks disabled"))
        vbp = prefix[:-1] + ["vbp"]
        site = docs / "blueprint/html-single"
        run_document_case("vbp-check", ["check", "--site", str(site)], tool=vbp)
        for selector in ("labels", "work-queue", "stats"):
            snapshots = []
            for kind in ("baseline", "blueprint"):
                result = subprocess.run(vbp + ["query", "--site", str(docs / kind / "html-single"), selector],
                                        cwd=repo, capture_output=True, text=True, check=True, timeout=60)
                snapshots.append(json.loads(result.stdout))
            assert snapshots[0] == snapshots[1], f"Blueprint {selector} changed after LSP enrichment"
        (docs / "semantic-comparison.json").write_text(json.dumps({
            "selectors": ["labels", "work-queue", "stats"], "unchanged": True}, indent=2) + "\n")
        print("Blueprint semantic comparison: passed", flush=True)
    print(f"evidence: {output}", flush=True)


if __name__ == "__main__":
    main()

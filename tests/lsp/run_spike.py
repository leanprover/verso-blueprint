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
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    prefix = [str(repo / "scripts/lean-low-priority"), "lake", "exe", "verso-lsp-spike"]
    identity = hashlib.sha256()
    for path in sorted([*(repo / "src/VersoLsp").glob("*.lean"),
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
    print(f"evidence: {output}", flush=True)


if __name__ == "__main__":
    main()

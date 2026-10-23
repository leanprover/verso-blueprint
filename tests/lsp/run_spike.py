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
    wrapper = str(repo / "scripts/lean-low-priority")
    package = repo / "packages/rosetta"
    for toolchain in (package / "lean-toolchain", package / "verso/lean-toolchain"):
        assert toolchain.read_text().strip() == (repo / "lean-toolchain").read_text().strip(), \
            f"package toolchain differs from this VBP checkout: {toolchain}"
    package_files = sorted(path for path in package.rglob("*")
                           if path.is_file() and not {".lake", ".beam", ".git", "__pycache__"}.intersection(path.parts)
                           and path.suffix != ".pyc")
    identity = hashlib.sha256()
    for path in sorted([*package_files,
                        *(repo / "tests/RosettaDocs").glob("*.lean"),
                        repo / "tests/RosettaDocsMain.lean",
                        repo / "lakefile.lean", repo / "lean-toolchain", repo / "lake-manifest.json",
                        *Path(__file__).parent.rglob("*")]):
        if path.is_file() and "__pycache__" not in path.parts:
            identity.update(str(path.relative_to(repo)).encode())
            identity.update(path.read_bytes())
            saved = output / "source" / path.relative_to(repo)
            saved.parent.mkdir(parents=True, exist_ok=True)
            saved.write_bytes(path.read_bytes())
    # Content-addressed, test-owned copy: no VBP sources or canonical build
    # outputs are available inside the proposed standalone repository.
    standalone = output / "standalone" / identity.hexdigest()[:16]
    standalone.mkdir(parents=True, exist_ok=True)
    for path in package_files:
        target = standalone / path.relative_to(package)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(path.read_bytes())
    prefix = [wrapper, "lake", "exe", "rosetta-spike"]
    metadata = {"sourceSha256": identity.hexdigest(),
                "leanToolchain": (repo / "lean-toolchain").read_text().strip(),
                "servers": {}}
    (output / "identity.json").write_text(json.dumps(metadata, indent=2) + "\n")
    cases = [("mock", None)]
    for language, command in (("rust", args.rust_command), ("rocq", args.rocq_command)):
        if command:
            project = output / "projects" / language
            shutil.copytree(standalone / "tests/lsp/projects" / language, project, dirs_exist_ok=True)
            version = subprocess.run([command, "--version"], capture_output=True, text=True,
                                     check=True, timeout=15).stdout.strip()
            metadata["servers"][language] = {"command": command, "version": version}
            cases.append((language, ["probe", language, command, str(project)]))
    (output / "identity.json").write_text(json.dumps(metadata, indent=2) + "\n")
    failed = []
    for name, case in cases:
        case_command = [wrapper, "lake", "test"] if case is None else prefix + case
        result = subprocess.run(case_command, cwd=standalone, capture_output=True,
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
        command = [wrapper, "lake", "exe", "rosetta-docs"]

        def run_document_case(name, arguments, tool=command, cwd=repo, expect_success=True):
            result = subprocess.run(tool + arguments, cwd=cwd, capture_output=True,
                                    text=True, timeout=120)
            (docs / f"{name}.stdout").write_text(result.stdout)
            (docs / f"{name}.stderr").write_text(result.stderr)
            if (result.returncode == 0) != expect_success:
                raise SystemExit(f"{name} had unexpected exit {result.returncode}:\n{result.stderr[-4000:]}")
            print(f"{name}: passed", flush=True)
            return result

        build = [wrapper, "lake", "build"]
        run_document_case("independent-core", [], tool=build, cwd=standalone)
        core_manifest = json.loads((standalone / "lake-manifest.json").read_text())
        assert core_manifest["packages"] == []
        bridge = standalone / "verso"
        bridge_manifest = json.loads((bridge / "lake-manifest.json").read_text())

        def warm_git_sources(target):
            cache = target / ".lake/packages"
            cache.mkdir(parents=True, exist_ok=True)
            for entry in bridge_manifest["packages"]:
                if entry["type"] != "git":
                    continue
                name = entry["name"].strip("«»")
                source = repo / ".lake/packages" / name
                actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
                assert actual == entry["rev"], f"warmed source revision differs: {name}"
                dirty = subprocess.check_output(
                    ["git", "status", "--porcelain", "--untracked-files=no"], cwd=source, text=True)
                assert not dirty, f"warmed dependency has tracked edits: {name}"
                destination = cache / name
                if not destination.exists():
                    destination.symlink_to(source.resolve(), target_is_directory=True)

        def assert_unavailable(name, module, cwd):
            source = cwd / "Unavailable.lean"
            source.write_text(f"import {module}\n")
            try:
                result = run_document_case(name, [source.name], tool=[wrapper, "lake", "lean"],
                                           cwd=cwd, expect_success=False)
                assert module in result.stderr + result.stdout
            finally:
                source.unlink()

        assert_unavailable("core-without-verso", "Verso", standalone)
        warm_git_sources(bridge)
        run_document_case("independent-bridge", [], tool=build, cwd=bridge)
        run_document_case("independent-bridge-tests", [], tool=[wrapper, "lake", "test"], cwd=bridge)
        bridge_names = {entry["name"].strip("«»") for entry in bridge_manifest["packages"]}
        assert "rosetta" in bridge_names and "verso" in bridge_names
        assert not {"VersoBlueprint", "lean_vir", "verso-slides", "proofwidgets"} & bridge_names
        assert_unavailable("bridge-without-blueprint", "VersoBlueprint", bridge)

        # Exercise the exact Git + subDir mechanism intended for publication,
        # using a local fixture repository rather than creating/pushing a remote.
        def git(*arguments):
            return subprocess.check_output(["git", *arguments], cwd=standalone,
                                           text=True, stderr=subprocess.STDOUT).strip()

        if not (standalone / ".git").exists():
            git("init", "-b", "main")
            git("config", "user.name", "Rosetta package tests")
            git("config", "user.email", "rosetta-tests@example.invalid")
        git("add", ".")
        if git("status", "--porcelain"):
            git("commit", "--no-gpg-sign", "-m", "test: package extraction snapshot")
        revision = git("rev-parse", "HEAD")
        repository_uri = standalone.as_uri()

        def git_consumer(name, dependency, imports, subdir=None):
            consumer = output / "consumers" / identity.hexdigest()[:16] / name
            consumer.mkdir(parents=True, exist_ok=True)
            (consumer / "lean-toolchain").write_text((standalone / "lean-toolchain").read_text())
            config = (f'name = "{name}"\ndefaultTargets = ["Consumer"]\n'
                      f'[[require]]\nname = "{dependency}"\ngit = {json.dumps(repository_uri)}\n'
                      f'rev = {json.dumps(revision)}\n')
            if subdir:
                config += f'subDir = {json.dumps(subdir)}\n'
            config += '[[lean_lib]]\nname = "Consumer"\n'
            (consumer / "lakefile.toml").write_text(config)
            (consumer / "Consumer.lean").write_text(imports)
            if subdir:
                warm_git_sources(consumer)
            run_document_case(name, [], tool=build, cwd=consumer)
            return json.loads((consumer / "lake-manifest.json").read_text())

        core_consumer = git_consumer("rosetta_consumer", "rosetta", "import Rosetta\n#check Rosetta.analyze\n")
        assert {entry["name"] for entry in core_consumer["packages"]} == {"rosetta"}
        bridge_consumer = git_consumer("verso_rosetta_consumer", "verso-rosetta",
                                      "import Rosetta\nimport VersoRosetta\n#check VersoRosetta.collect\n", "verso")
        consumer_names = {entry["name"].strip("«»") for entry in bridge_consumer["packages"]}
        assert {"rosetta", "verso-rosetta", "verso"} <= consumer_names
        assert not {"VersoBlueprint", "lean_vir", "verso-slides", "proofwidgets"} & consumer_names
        (docs / "package-boundaries.json").write_text(json.dumps({
            "repositoryRevision": revision, "corePackages": [],
            "bridgePackages": sorted(bridge_names), "bridgeConsumerPackages": sorted(consumer_names),
            "coreCannotImportVerso": True, "bridgeCannotImportBlueprint": True,
            "gitConsumersBuilt": True}, indent=2) + "\n")
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
        vbp = [wrapper, "lake", "exe", "vbp"]
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

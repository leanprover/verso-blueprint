#!/usr/bin/env python3
"""Exercise saved mock-review bindings through rebuilt Lean artifacts.

Run inside the maintainer's whole-tree resource cap. Only the owner fixture is
edited, with its exact original bytes restored even on ordinary failure. No
mtime tricks, cache deletion, production review receipts, or native success mocks.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    owner = root / "tests/VersoBlueprintTests/BlueprintAssessmentSnapshot/Owner.lean"
    consumer = owner.parent.with_suffix(".lean")
    original = owner.read_bytes()
    consumer_bytes = consumer.read_bytes()
    proof = b"theorem witness : True := True.intro"
    mapping = b"The prose statement corresponds to the selected Lean proposition."
    prose = "The proposition is true. Ω 🧭 The Lean declaration provides its proof.".encode("utf-8")
    proof_use = b'(proofUses := ["assessment.docDependencyA"])'
    docstring = "/-- The attribute statement is true. Ω 🧭 -/".encode("utf-8")
    local_doc_proof = b"theorem localDoc (x : Nat) : x = x := by rfl"
    local_doc_target = b"{name}`x` with {Lean.Doc.lean}`x`"
    highlighted_doc = "theorem modelAReviewed (x y : Nat) : x ≤ y → x ≤ y := id".encode("utf-8")
    macro_rule = b"macro_rules | `(underBinder $v:ident) => `(fun (_inner : Nat) => $v)"
    inner_binder_rule = b"macro_rules | `(underBinder $v:ident) => `(fun ($v : Nat) => $v)"
    header_use = b'(uses := "assessment.docDependencyA")'
    markers = (proof, mapping, prose, proof_use, docstring, local_doc_proof, local_doc_target,
        highlighted_doc, macro_rule, header_use)
    if any(original.count(marker) != 1 for marker in markers):
        raise RuntimeError("Expected exact source-edit fixture baseline")
    swapped = original.replace(proof_use, proof_use.replace(b"docDependencyA", b"docDependencyB"))
    variants = [
        ("rewrite", original.replace(proof, b"theorem witness : True := by exact True.intro")),
        ("hole", original.replace(proof, b"theorem witness : True := by sorry")),
        ("statement", original.replace(proof,
            "theorem witness : True ∧ True := And.intro True.intro True.intro".encode("utf-8"))),
        ("mapping", original.replace(mapping, b"The prose preserves a different explicit interpretation.")),
        ("prose", original.replace(
            prose,
            "The proposition remains true. Ω 🧭 A different proof is described here.".encode("utf-8"))),
        ("docstring-proof-use", swapped),
        ("docstring-text", swapped.replace(docstring, docstring.replace(b"statement is true", b"statement is still true"))),
        ("local-doc-proof", original.replace(local_doc_proof,
            b"theorem localDoc (x : Nat) : x = x := by\n  have h : x = x := rfl\n  exact h")),
        ("local-doc-target", original.replace(local_doc_target,
            b"{name (full := BlueprintAssessmentSnapshot.DocTargets.x)}`x` with {Lean.Doc.lean}`x`")),
        ("directive-header-use", original.replace(header_use, header_use.replace(b"docDependencyA", b"docDependencyB"))),
        ("highlighted-doc-proof", original.replace(highlighted_doc,
            highlighted_doc.removesuffix(b"id") + b"fun h => by exact h")),
        ("highlighted-doc-position", original.replace(highlighted_doc,
            "theorem modelAReviewed (y x : Nat) : y ≤ x → y ≤ x := id".encode("utf-8"))),
        ("highlighted-doc-macro", original.replace(macro_rule, inner_binder_rule)),
    ]
    commands = []

    def interrupted(_signum, _frame):
        raise RuntimeError("Interrupted: restoring fixture bytes")

    signal.signal(signal.SIGTERM, interrupted)

    def run(step, arguments, mode=None, control=None):
        environment = dict(os.environ)
        if mode is not None:
            environment["VBP_SNAPSHOT_MODE"] = mode
            environment["VBP_SNAPSHOT_REVIEW_CONTROL"] = str(control)
        command = [str(root / "scripts/lean-low-priority"), "lake", *arguments]
        start = time.monotonic()
        with (output / f"{step}.log").open("w") as log:
            result = subprocess.run(command, cwd=root, env=environment,
                stdout=log, stderr=subprocess.STDOUT, timeout=180)
        commands.append({"step": step, "arguments": arguments,
            "seconds": time.monotonic() - start, "exit": result.returncode})
        print(f"{step}: exit {result.returncode}", flush=True)
        if result.returncode:
            raise RuntimeError(f"Failed {step}; see its retained log")
        if consumer.read_bytes() != consumer_bytes:
            raise RuntimeError("Consumer changed during source-edit controls")

    def build(step):
        run(step, ["build", "+VersoBlueprintTests.BlueprintAssessmentSnapshot.Owner:olean"])

    def query(step, mode, control):
        run(step, ["lean", str(consumer.relative_to(root))], mode, control)

    try:
        with tempfile.TemporaryDirectory(prefix="vbp-snapshot-review-") as temporary:
            control = Path(temporary) / "mock-review-binding.txt"
            build("baseline-setup")
            query("baseline-capture", "capture", control)
            for mode, content in variants:
                owner.write_bytes(content)
                build(mode + "-setup")
                query(mode + "-capture", mode, control)
            owner.write_bytes(original)
            build("restored-setup")
            query("restored-capture", "rewrite", control)
    finally:
        owner.write_bytes(original)
        receipt = {
            "owner_restored": owner.read_bytes() == original,
            "consumer_unchanged": consumer.read_bytes() == consumer_bytes,
            "owner_sha256": hashlib.sha256(original).hexdigest(),
            "consumer_sha256": hashlib.sha256(consumer_bytes).hexdigest(),
            "commands": commands,
            "reviews": "explicitly MOCK test judgments; native observations are real",
        }
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()

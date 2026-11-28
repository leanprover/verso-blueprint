/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

namespace Informal.PageBehavior

structure JsConfig where
  proofHider : Bool := false
  hashReveal : Bool := false
deriving Inhabited, Repr

private def jsTemplate : String := r##"(function () {
  const targetClass = "bp_decl_target";
  const targetBlockClass = "bp_decl_target_block";
  const enableProofHider = __BP_ENABLE_PROOF_HIDER__;
  const enableHashReveal = __BP_ENABLE_HASH_REVEAL__;

  function installProofHider() {
    const blocks = document.querySelectorAll("details.bp_code_block code.hl.lean.block");
    const declKeywords = new Set(["theorem", "lemma", "corollary", "example"]);
    const commandStartKeywords = new Set([
      "theorem", "lemma", "corollary", "example", "def", "abbrev", "instance",
      "axiom", "constant", "opaque", "inductive", "structure", "class", "namespace",
      "section", "end", "open", "local", "attribute", "set_option", "variable",
      "variables", "notation", "infix", "infixl", "infixr", "prefix", "postfix",
      "macro", "syntax", "elab", "initialize", "mutual"
    ]);

    function locateTextPosition(rootNode, absIndex) {
      const walker = document.createTreeWalker(rootNode, NodeFilter.SHOW_TEXT);
      let seen = 0;
      while (true) {
        const node = walker.nextNode();
        if (!node) break;
        const len = node.nodeValue ? node.nodeValue.length : 0;
        if (absIndex <= seen + len) {
          return { node, offset: absIndex - seen };
        }
        seen += len;
      }
      return null;
    }

    function toggleProof(toggleNode, proofTail, gapNode) {
      const hidden = proofTail.classList.toggle("bp-proof-tail-hidden");
      toggleNode.classList.toggle("bp-proof-open", !hidden);
      toggleNode.setAttribute("aria-expanded", hidden ? "false" : "true");
      if (gapNode) {
        gapNode.classList.toggle("bp-proof-gap-hidden", !hidden);
      }
    }

    function absIndexBeforeElement(rootNode, el) {
      const r = document.createRange();
      r.setStart(rootNode, 0);
      r.setEndBefore(el);
      return r.toString().length;
    }

    function lineIndent(text, idx) {
      const lastNl = text.lastIndexOf("\n", Math.max(0, idx - 1));
      const lineStart = lastNl + 1;
      let i = lineStart;
      while (i < idx && text[i] === " ") i++;
      return i - lineStart;
    }

    function isFirstTokenOnLine(text, idx) {
      const lastNl = text.lastIndexOf("\n", Math.max(0, idx - 1));
      const lineStart = lastNl + 1;
      return /^[ \t]*$/.test(text.slice(lineStart, idx));
    }

    function isCommandStartText(tokText) {
      if (!tokText) return false;
      if (tokText[0] === "#") return true;
      return commandStartKeywords.has(tokText);
    }

    blocks.forEach((block) => {
      if (!(block instanceof HTMLElement)) return;
      const details = block.closest("details.bp_code_block");
      if (details instanceof HTMLElement && details.dataset.bpProofFold === "off") return;
      if (block.dataset.bpProofHider === "1") return;
      block.dataset.bpProofHider = "1";

      const text = block.textContent || "";
      if (!text) return;

      const tokenNodes = Array.from(block.querySelectorAll(".token"));
      const keywordNodes = Array.from(block.querySelectorAll(".keyword.token"));

      const allTokens = tokenNodes.map((el) => {
        const tokText = (el.textContent || "").trim();
        const start = absIndexBeforeElement(block, el);
        const end = start + (el.textContent || "").length;
        const firstOnLine = isFirstTokenOnLine(text, start);
        const indent = lineIndent(text, start);
        return { el, tokText, start, end, firstOnLine, indent };
      });

      const commandStarts = allTokens.filter((t) =>
        t.firstOnLine && isCommandStartText(t.tokText)
      );

      const keywordTokens = keywordNodes.map((el) => {
        const tokText = (el.textContent || "").trim();
        const start = absIndexBeforeElement(block, el);
        const end = start + (el.textContent || "").length;
        const indent = lineIndent(text, start);
        return { el, tokText, start, end, indent };
      });

      const declStarts = keywordTokens.filter((t) => declKeywords.has(t.tokText));
      if (declStarts.length === 0) return;

      const segments = [];
      for (const decl of declStarts) {
        const boundary = commandStarts.find((c) =>
          c.start > decl.start && c.indent <= decl.indent
        );
        const segmentEnd = boundary ? boundary.start : text.length;
        if (segmentEnd <= decl.start) continue;
        const byTok = keywordTokens.find((t) =>
          t.tokText === "by" && t.start > decl.start && t.end <= segmentEnd
        );
        if (!byTok) continue;
        let hideStart = byTok.end;
        if (hideStart >= segmentEnd) continue;
        const gapText = text.slice(hideStart, segmentEnd).includes("\n") ? "\n" : "";
        segments.push({
          byEl: byTok.el,
          byStart: byTok.start,
          byEnd: byTok.end,
          hideStart,
          hideEnd: segmentEnd,
          gapText
        });
      }
      if (segments.length === 0) return;

      for (let i = segments.length - 1; i >= 0; i--) {
        const seg = segments[i];
        const hideStartPos = locateTextPosition(block, seg.hideStart);
        const hideEndPos = locateTextPosition(block, seg.hideEnd);
        if (!hideStartPos || !hideEndPos) continue;
        const hideRange = document.createRange();
        hideRange.setStart(hideStartPos.node, hideStartPos.offset);
        hideRange.setEnd(hideEndPos.node, hideEndPos.offset);
        const fragment = hideRange.extractContents();
        if (!fragment.textContent || fragment.textContent.length === 0) continue;

        const proofTail = document.createElement("span");
        proofTail.className = "bp-proof-tail bp-proof-tail-hidden";
        proofTail.appendChild(fragment);
        hideRange.insertNode(proofTail);
        let gapNode = null;
        if (seg.gapText) {
          gapNode = document.createElement("span");
          gapNode.textContent = seg.gapText;
          proofTail.parentNode.insertBefore(gapNode, proofTail);
        }

        const toggle = seg.byEl;
        if (!(toggle instanceof HTMLElement)) continue;
        toggle.classList.add("bp-proof-by-toggle");
        toggle.tabIndex = 0;
        toggle.setAttribute("role", "button");
        toggle.setAttribute("aria-expanded", "false");
        toggle.setAttribute("aria-label", "Toggle proof");
        toggle.addEventListener("click", function () {
          toggleProof(toggle, proofTail, gapNode);
        });
        toggle.addEventListener("keydown", function (ev) {
          if (!(ev instanceof KeyboardEvent)) return;
          if (ev.key !== "Enter" && ev.key !== " ") return;
          ev.preventDefault();
          toggleProof(toggle, proofTail, gapNode);
        });
      }
    });
  }

  function openDetailsAncestors(elem) {
    let cur = elem;
    while (cur) {
      if (cur.tagName === "DETAILS") {
        cur.setAttribute("open", "open");
      }
      cur = cur.parentElement;
    }
  }

  function revealDeclFromHash() {
    const hash = window.location.hash;
    if (!hash || hash.length < 2) return;
    const id = decodeURIComponent(hash.slice(1));
    const target = document.getElementById(id);
    if (!target) return;
    openDetailsAncestors(target);
    document.querySelectorAll("." + targetClass).forEach((el) => el.classList.remove(targetClass));
    document.querySelectorAll("." + targetBlockClass).forEach((el) => el.classList.remove(targetBlockClass));
    target.classList.remove(targetClass);
    void target.offsetWidth;
    target.classList.add(targetClass);
    const block = target.closest("code.hl.lean.block, pre.hl.lean, .example-file");
    if (block) {
      block.classList.remove(targetBlockClass);
      void block.offsetWidth;
      block.classList.add(targetBlockClass);
    }
    target.scrollIntoView({ block: "center", inline: "nearest", behavior: "smooth" });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      if (enableProofHider) installProofHider();
      if (enableHashReveal) revealDeclFromHash();
    });
  } else {
    if (enableProofHider) installProofHider();
    if (enableHashReveal) revealDeclFromHash();
  }

  if (enableHashReveal) {
    window.addEventListener("hashchange", revealDeclFromHash);
    document.addEventListener("click", function (ev) {
      const target = ev.target;
      if (!(target instanceof Element)) return;
      const a = target.closest("a[href]");
      if (!a) return;
      const url = new URL(a.getAttribute("href"), window.location.href);
      if (url.pathname !== window.location.pathname || !url.hash) return;
      if (decodeURIComponent(url.hash) !== window.location.hash) return;
      setTimeout(revealDeclFromHash, 0);
    });
  }
})();"##

private def boolLit (b : Bool) : String :=
  if b then "true" else "false"

def js (cfg : JsConfig := {}) : String :=
  (jsTemplate.replace "__BP_ENABLE_PROOF_HIDER__" (boolLit cfg.proofHider)).replace
    "__BP_ENABLE_HASH_REVEAL__" (boolLit cfg.hashReveal)

def jsInteractive : String := js { proofHider := true, hashReveal := true }

end Informal.PageBehavior

# UPC-0024 Expose Verso Lean Fence Source Mapping

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-verso
Last reviewed: 2026-11-28
Owner: none
Issue: none linked
PR: none linked
Related cards: UPC-0023, UPC-0025

## Summary

Expose the original literal range and its mapping to the padded Lean input during Verso fence elaboration.

## Impact

This improves editor navigation and diagnostics for embedded Lean. Capture uses compiled declarations and registration text copied at elaboration. It no longer needs the physical fence or its padded buffer.

## Roadmap Decision

Track as an upstream improvement. Current compiled-artifact capture is independent
of this API.

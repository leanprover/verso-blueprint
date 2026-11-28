# UPC-0025 Expose Loaded-Module Verified Source Query

Status: open
Kind: upstream-api
Priority: medium
Origin: upstream-lake
Last reviewed: 2026-11-28
Owner: none
Issue: none linked
PR: none linked
Related cards: UPC-0020, UPC-0023, UPC-0024

## Summary

Expose a supported Lean/Lake query mapping the public and server artifacts of a loaded module to its compiler input path and digest.

## Impact

A verified path could improve presentation links with multiple checkouts or sibling path dependencies. Capture uses the loaded artifacts and needs no trace, source file, or source verification query.

## Roadmap Decision

Track as an upstream improvement. Current compiled-artifact capture is independent
of this API.

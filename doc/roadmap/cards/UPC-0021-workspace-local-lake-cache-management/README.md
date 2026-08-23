# UPC-0021 Workspace-Local Lake Cache Management

Status: candidate
Kind: upstream-api
Priority: low
Origin: upstream-lake
Last reviewed: 2026-08-22
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: `scripts/with-blueprint-lake-cache` and its dedicated tests and documentation
Related cards: UPC-0019, UPC-0020

## Summary

Lake should provide a coherent workspace-local surface for selecting, enabling,
inspecting, and pruning its local artifact cache without requiring a shell
wrapper or turning maintainer policy into published package policy.

## Impact

Blueprint currently wraps every maintainer Lake command to select a shared,
exact-toolchain cache and default to writable, cache-in-place artifacts. The
wrapper works, but duplicates policy and administration that should eventually
be native to Lake and makes plain `lake` invocations behave differently from
the documented maintainer entry points.

## Roadmap Decision

Keep the wrapper for the initial artifact-cache rollout. Before proposing an
upstream interface, audit current Lake main and agree which controls belong to
workspace-local configuration rather than package metadata. Remove the wrapper
once Lake can express and administer the required policy directly.

## Reproduction Status

This is a tooling and ownership gap rather than a build failure. Lean v4.33
provides package fields and environment variables for cache enablement and
restoration, plus individual cache commands, but VBP still needs a wrapper to
compose its local policy and shared exact-toolchain cache location.

## Preliminary Analysis

Putting `enableArtifactCache` and `restoreAllArtifacts` directly in VBP's
package configuration would publish those choices to downstream workspaces and
give the package values stronger precedence than workspace defaults. Environment
variables retain local override behavior, but require an external launcher.

## Scope Boundary

This card owns local cache configuration and administration. Module-level input
dependencies remain UPC-0019; compatibility with consumers that bypass Lake's
resolved artifact paths remains UPC-0020. It does not request remote artifact
transport.

## Expected Behavior

A workspace can use Lake-native configuration and commands to:

- select a shared cache while preserving exact-toolchain isolation
- control cache writes and artifact restoration without imposing policy on
  downstream users of the package
- inspect the effective cache policy and resolved cache directory
- prune a selected toolchain partition safely
- override the local defaults for one invocation

## Evidence

- Local policy wrapper: `scripts/with-blueprint-lake-cache`
- Wrapper composition point: `scripts/lean-low-priority`
- Maintainer documentation: `doc/MAINTAINER_GUIDE.md#shared-lake-artifact-cache`
- Lean v4.33 controls: `enableArtifactCache`, `restoreAllArtifacts`,
  `LAKE_CACHE_DIR`, `LAKE_ARTIFACT_CACHE`, and `LAKE_RESTORE_ARTIFACTS`

## Current Workaround

Run maintainer Lake commands through `scripts/lean-low-priority`, which applies
the repository-local cache wrapper while preserving explicit environment
overrides.

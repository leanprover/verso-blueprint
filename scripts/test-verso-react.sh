#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VIR_SDK_ARCHIVE:?Select the SDK archive matching the pinned VIR commit}"
: "${VBP_RENDERER_REPORT_DIR:?Select an output directory under repository-root _out/<worktree>}"
export VIR_SDK_EXPECT_COMMIT
VIR_SDK_EXPECT_COMMIT=$(node -e 'const m = require("./lake-manifest.json"); console.log(m.packages.find(p => p.name === "lean_vir").rev)')

# Retain restoration until this consumer has a separate cache-only acceptance.
LAKE_RESTORE_ARTIFACTS=true scripts/lean-low-priority lake build \
  +VersoReactTests:vir +VersoBlueprintVirTests.Renderer:vir :virSdk
scripts/lean-low-priority node tests/vir_preview/renderer_package_smoke.mjs

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VIR_SDK_ARCHIVE:?Select the SDK archive matching the pinned VIR commit}"
: "${VBP_NATIVE_SESSION_REPORT:?Select a report path under repository-root _out/<worktree>}"
export VIR_SDK_EXPECT_COMMIT
VIR_SDK_EXPECT_COMMIT=$(node -e 'const m = require("./lake-manifest.json"); console.log(m.packages.find(p => p.name === "lean_vir").rev)')

# Scoped workaround for the reviewed VIR packaging/cache-in-place import bug.
LAKE_RESTORE_ARTIFACTS=true scripts/lean-low-priority lake build \
  +VersoBlueprintVirTests.NativeSession:vir :virSdk
scripts/lean-low-priority node tests/vir_preview/session_browser_smoke.mjs

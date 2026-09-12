#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VIR_SDK_ARCHIVE:?Select the SDK archive matching the pinned VIR commit}"
: "${VBP_NATIVE_PREVIEW_REPORT:?Select a report path under repository-root _out/<worktree>}"
export VIR_SDK_EXPECT_COMMIT
VIR_SDK_EXPECT_COMMIT=$(node -e 'const m = require("./lake-manifest.json"); console.log(m.packages.find(p => p.name === "lean_vir").rev)')

# Scoped workaround for the reviewed VIR :vir cache-in-place import bug.
fixtureTarget=+VersoBlueprintVirTests.NativePreview:vir
if [[ "${1:-}" == "--string-preview" ]]; then
  fixtureTarget=+VersoBlueprintVirTests.StringPreview:vir
elif [[ "${1:-}" == "--embedded-preview" ]]; then
  # The shell packages the imported component from the live server snapshot.
  fixtureTarget=+VersoBlueprintVirTests.EmbeddedPreviewServer
fi
LAKE_RESTORE_ARTIFACTS=true scripts/lean-low-priority lake build \
  "$fixtureTarget" @lean_vir/+Vir.Infoview :virSdk
# Supply downstream imports to the reused harness, whose server cwd is VIR.
LAKE_RESTORE_ARTIFACTS=true scripts/lean-low-priority lake env \
  node tests/vir_preview/native_browser_smoke.mjs "$@"

#!/usr/bin/env bash

set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$package_root"

python3 scripts/check-module-boundaries.py
./scripts/lean-low-priority lake build VersoBlueprintModuleTests
./scripts/lean-low-priority lake test
./scripts/lean-low-priority lake build vbp
python3 tests/integration/check_lean_run_external_markup.py
python3 tests/integration/check_embedded_asset_cache.py
python3 tests/integration/check_vbp_failure_protocol.py

#!/usr/bin/env bash

set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$package_root"

./scripts/lean-low-priority lake test
python3 tests/integration/check_lean_run_external_markup.py

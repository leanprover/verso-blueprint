#!/usr/bin/env bash

set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$package_root"

exec python3 -m scripts.blueprint_test_blueprints generate-all "$@"

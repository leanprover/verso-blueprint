#!/usr/bin/env bash

set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$package_root"

if [ "${1:-}" = "--help" ]; then
  cat <<'EOF'
usage: ./scripts/validate-branch.sh [pytest args...]

Run the full branch-validation workflow:

- Lean tests
- Python harness/unit tests
- reference blueprint generation under `_out/reference-blueprints/`
- test blueprint generation under `_out/test-blueprints/`
- configured standalone test-blueprint regressions

Any extra arguments are forwarded to the final pytest invocation.
EOF
  exit 0
fi

./scripts/run-lean-tests.sh

python3 -m unittest discover -s tests/harness -p 'test_*.py'

./scripts/generate-reference-blueprints.sh
./scripts/validate-test-blueprints.sh "$@"

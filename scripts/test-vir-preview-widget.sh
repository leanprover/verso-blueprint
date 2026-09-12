#!/usr/bin/env bash
set -euo pipefail

# Real registered shell, live snapshot package, workspace asset and preview RPCs.
exec "$(dirname "$0")/test-vir-native-preview.sh" --embedded-preview

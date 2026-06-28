#!/usr/bin/env bash
set -euo pipefail

npm run docs
npm run check:docs

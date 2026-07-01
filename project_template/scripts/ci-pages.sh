#!/usr/bin/env bash

set -euo pipefail

lake build ProjectTemplate
lake lean ProjectTemplateMain.lean -- --run ProjectTemplateMain.lean --output _out/site

test -f _out/site/html-multi/index.html
test -f _out/site/html-multi/-verso-data/blueprint-manifest.json
test -f _out/site/html-multi/-verso-data/blueprint-html-cache.json

#!/usr/bin/env bash
# Root buck2 check target: the repo shape is green. Runs from the project root.
set -euo pipefail
exec just doctor

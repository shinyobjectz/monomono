#!/usr/bin/env bash
# Definition of green. GitHub Actions and `just ci run` both call this.
set -euo pipefail
cd "$(dirname "$0")/../../.."
exec just check

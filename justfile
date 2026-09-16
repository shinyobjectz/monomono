# monomono — this repo is its own first consumer. Package recipes come from mono.just.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

import 'mono.just'

# Scaffold a throwaway consumer from this checkout and run its check
selftest:
    @./test/init.sh

# Tag and push a release: just release 0.2.0
[positional-arguments]
release version:
    @./scripts/tools/release.sh "$1"

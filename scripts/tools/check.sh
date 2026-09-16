#!/usr/bin/env bash
# Definition of green. CI and `just check` both run this.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

"$MONO_HOME/scripts/tools/doctor.sh"
if mono_module context; then
  "$MONO_HOME/scripts/tools/context/feature.sh" check
fi
"$MONO_HOME/scripts/tools/agents-host.sh" check
"$MONO_HOME/scripts/build/buck.sh" build
"$MONO_HOME/scripts/build/buck.sh" test
echo "green"

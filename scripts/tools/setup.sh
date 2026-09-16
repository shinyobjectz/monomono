#!/usr/bin/env bash
# First clone / new machine: buck2, host adapters, stores, package adapters, submodules, ci.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

if ! command -v buck2 >/dev/null 2>&1; then
  "$MONO_HOME/scripts/tools/install-buck2.sh" || echo "buck2 not installed; install it and rerun just setup" >&2
fi
"$MONO_HOME/scripts/tools/agents-host.sh" sync --force
if mono_module context && command -v sqlite3 >/dev/null 2>&1; then
  "$MONO_HOME/scripts/tools/context/db.sh" init
fi
"$MONO_HOME/scripts/update/pkg.sh" ensure
"$MONO_HOME/scripts/tools/submodule.sh" update
if [[ -d $MONO_CI/github ]]; then
  "$MONO_HOME/scripts/tools/ci.sh" sync
fi
"$MONO_HOME/scripts/tools/doctor.sh"

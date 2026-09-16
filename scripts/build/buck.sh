#!/usr/bin/env bash
# buck2 wrappers. The build graph lives in BUCK files; this only picks defaults.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

require_cmd buck2
cd "$MONO_ROOT"

verb=${1:-build}
shift || true
if [[ $verb == build ]]; then
  for hook in "$MONO_ROOT/scripts/hooks/pre-build.sh" "$MONO_ROOT/scripts/hooks/pre-build.lua"; do
    [[ -f $hook ]] || continue
    "$MONO_HOME/scripts/tools/run-script.sh" hooks pre-build
    break
  done
fi
case "$verb" in
  build|test|targets)
    if [[ $# -eq 0 ]]; then
      set -- "//..."
    fi
    exec buck2 "$verb" "$@"
    ;;
  run)
    [[ $# -gt 0 ]] || die "usage: just run <target> [args...]"
    exec buck2 run "$@"
    ;;
  *) exec buck2 "$verb" "$@" ;;
esac

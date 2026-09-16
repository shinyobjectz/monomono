#!/usr/bin/env bash
# Mix / Hex. mix.exs and mix.lock stay here; add deps by editing mix.exs, then sync.
set -euo pipefail
cd "$PKG_DIR"
case "${1:-}" in
  ensure)
    command -v mix >/dev/null || { echo "mix not installed" >&2; exit 1; }
    [[ -f mix.exs ]] || { echo "create mix.exs in $PKG_DIR (mix new --app $PKG_ECO .)" >&2; exit 1; } ;;
  add) shift; echo "mix has no add; put {:$1, \"~> x.y\"} in mix.exs deps then just pkg sync $PKG_ECO" >&2; exit 2 ;;
  update) shift; mix deps.update "${@:---all}" ;;
  sync) mix deps.get ;;
  *) echo "mix adapter: ensure|add|update|sync" >&2; exit 2 ;;
esac

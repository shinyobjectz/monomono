#!/usr/bin/env bash
# LuaRocks tree. rocks.txt lists what is installed; tree/ holds it. Expose tree/share/lua/5.4 as a lua_library root.
set -euo pipefail
cd "$PKG_DIR"
case "${1:-}" in
  ensure)
    command -v luarocks >/dev/null || { echo "luarocks not installed" >&2; exit 1; }
    mkdir -p tree; touch rocks.txt ;;
  add) shift; for r in "$@"; do luarocks --tree ./tree install "$r"; grep -qx "$r" rocks.txt || echo "$r" >>rocks.txt; done ;;
  update) shift; while read -r r; do [[ -n $r ]] && luarocks --tree ./tree install "$r"; done <rocks.txt ;;
  sync) while read -r r; do [[ -n $r ]] && luarocks --tree ./tree install "$r"; done <rocks.txt ;;
  *) echo "luarocks adapter: ensure|add|update|sync" >&2; exit 2 ;;
esac

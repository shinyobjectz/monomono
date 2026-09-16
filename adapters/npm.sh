#!/usr/bin/env bash
# npm workspace. Same shape as bun, npm as the client.
set -euo pipefail
cd "$PKG_DIR"
case "${1:-}" in
  ensure)
    command -v npm >/dev/null || { echo "npm not installed" >&2; exit 1; }
    [[ -f package.json ]] || printf '{\n  "name": "%s",\n  "private": true,\n  "workspaces": []\n}\n' "$PKG_ECO" >package.json ;;
  add) shift; npm install "$@" ;;
  update) shift; npm update "$@" ;;
  sync) npm install ;;
  *) echo "npm adapter: ensure|add|update|sync" >&2; exit 2 ;;
esac

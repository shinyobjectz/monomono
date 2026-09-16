#!/usr/bin/env bash
# Cargo workspace. Cargo.toml and Cargo.lock stay here; crates elsewhere are workspace members.
set -euo pipefail
cd "$PKG_DIR"
case "${1:-}" in
  ensure)
    command -v cargo >/dev/null || { echo "cargo not installed" >&2; exit 1; }
    [[ -f Cargo.toml ]] || printf '[workspace]\nresolver = "2"\nmembers = []\n' >Cargo.toml ;;
  add) shift; cargo add "$@" ;;
  update) shift; cargo update "$@" ;;
  sync) cargo fetch ;;
  *) echo "cargo adapter: ensure|add|update|sync" >&2; exit 2 ;;
esac

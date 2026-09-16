#!/usr/bin/env bash
# uv project. pyproject.toml, uv.lock, and .venv stay here.
set -euo pipefail
cd "$PKG_DIR"
case "${1:-}" in
  ensure)
    command -v uv >/dev/null || { echo "uv not installed" >&2; exit 1; }
    [[ -f pyproject.toml ]] || uv init --bare --name "$PKG_ECO" . >/dev/null ;;
  add) shift; uv add "$@" ;;
  update) shift; uv lock --upgrade "$@" ;;
  sync) uv sync ;;
  *) echo "uv adapter: ensure|add|update|sync" >&2; exit 2 ;;
esac

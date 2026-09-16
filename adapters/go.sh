#!/usr/bin/env bash
# Go module. go.mod and go.sum stay here.
set -euo pipefail
cd "$PKG_DIR"
case "${1:-}" in
  ensure)
    command -v go >/dev/null || { echo "go not installed" >&2; exit 1; }
    [[ -f go.mod ]] || go mod init "$PKG_ECO" ;;
  add) shift; go get "$@" ;;
  update) shift; go get -u "${@:-./...}" ;;
  sync) go mod download && go mod tidy ;;
  *) echo "go adapter: ensure|add|update|sync" >&2; exit 2 ;;
esac

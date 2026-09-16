#!/usr/bin/env bash
# Machine install. One curl delivers everything a monomono repo needs on a host:
#   just, buck2, and the `monomono` bootstrap command, all under ~/.local/bin.
#
#   curl -fsSL https://raw.githubusercontent.com/shinyobjectz/monomono/main/install.sh | bash
#
# Env: MONO_BIN_DIR (default ~/.local/bin), MONOMONO_HOME (default ~/.monomono), BUCK2_RELEASE (default latest).
# Re-running upgrades the bootstrap checkout and buck2. It never touches a repo.

set -euo pipefail

REPO="${MONO_REPO_URL:-https://github.com/shinyobjectz/monomono}"
BIN="${MONO_BIN_DIR:-$HOME/.local/bin}"
HOME_DIR="${MONOMONO_HOME:-$HOME/.monomono}"
mkdir -p "$BIN"

say() { echo "monomono: $*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "monomono: $1 is required ($2)" >&2; exit 1; }; }
need git "https://git-scm.com"
need curl "any package manager"

# 1. the bootstrap checkout
if [[ -d $HOME_DIR/.git ]]; then
  git -C "$HOME_DIR" fetch -q --tags origin
  git -C "$HOME_DIR" checkout -q main 2>/dev/null || true
  git -C "$HOME_DIR" pull -q --ff-only origin main
  say "updated $HOME_DIR"
else
  rm -rf "$HOME_DIR"
  git -c protocol.file.allow=always clone -q "$REPO" "$HOME_DIR"
  say "cloned $REPO to $HOME_DIR"
fi
ln -sfn "$HOME_DIR/bin/monomono" "$BIN/monomono"
say "linked $BIN/monomono"

# 2. just
if command -v just >/dev/null 2>&1; then
  say "just $(just --version | awk '{print $2}') present"
else
  curl --proto '=https' --tlsv1.2 -fsSL https://just.systems/install.sh | bash -s -- --to "$BIN" >/dev/null
  say "installed just to $BIN"
fi

# 3. buck2
if command -v buck2 >/dev/null 2>&1 && [[ -z ${BUCK2_RELEASE:-} ]]; then
  say "buck2 $(buck2 --version | awk '{print $2}') present"
else
  MONO_BIN_DIR="$BIN" bash "$HOME_DIR/scripts/tools/install-buck2.sh" | tail -n 1 | sed 's/^/monomono: /'
fi

# 4. optional: sqlite3 for the context junk drawer
command -v sqlite3 >/dev/null 2>&1 || say "sqlite3 not found; the context junk drawer needs it (optional)"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo; say "add to your shell profile:  export PATH=\"$BIN:\$PATH\"" ;;
esac
echo
say "ready. start a repo with:"
echo "    mkdir myrepo && cd myrepo && git init && monomono init && just setup && just check"

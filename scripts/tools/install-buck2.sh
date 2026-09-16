#!/usr/bin/env bash
# Install a prebuilt buck2 from GitHub releases into MONO_BIN_DIR (default ~/.local/bin).
# Pin with BUCK2_RELEASE=<tag>; default is the rolling "latest" release.

set -euo pipefail

release="${BUCK2_RELEASE:-latest}"
bin_dir="${MONO_BIN_DIR:-$HOME/.local/bin}"

os=$(uname -s)
arch=$(uname -m)
case "$os-$arch" in
  Darwin-arm64) triple="aarch64-apple-darwin" ;;
  Darwin-x86_64) triple="x86_64-apple-darwin" ;;
  Linux-x86_64) triple="x86_64-unknown-linux-gnu" ;;
  Linux-aarch64) triple="aarch64-unknown-linux-gnu" ;;
  *) echo "no prebuilt buck2 for $os $arch; see https://buck2.build/docs/about/getting_started/" >&2; exit 1 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v zstd >/dev/null 2>&1 || { echo "zstd is required to unpack buck2 (brew install zstd / apt install zstd)" >&2; exit 1; }

url="https://github.com/facebook/buck2/releases/download/$release/buck2-$triple.zst"
mkdir -p "$bin_dir"
tmp=$(mktemp -d)/buck2
echo "downloading $url"
curl -fsSL "$url" -o "$tmp.zst"
zstd -dq "$tmp.zst" -o "$tmp"
chmod +x "$tmp"
mv "$tmp" "$bin_dir/buck2"
rm -rf "$(dirname "$tmp")"
echo "installed $("$bin_dir/buck2" --version 2>/dev/null | head -n 1) to $bin_dir/buck2"
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "add $bin_dir to PATH" ;;
esac

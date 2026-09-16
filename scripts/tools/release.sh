#!/usr/bin/env bash
# Cut a release: VERSION, commit, tag, push. Run from a clean main.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
v=${1-}
[[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: just release X.Y.Z" >&2; exit 2; }
cd "$root"
[[ -z $(git status --porcelain) ]] || { echo "working tree not clean" >&2; exit 1; }
echo "$v" >VERSION
sed -i.bak -E "s/^version = \".*\"/version = \"$v\"/" mono.toml && rm -f mono.toml.bak
git add VERSION mono.toml
git commit -q -m "Release $v"
git tag -a "v$v" -m "monomono $v"
git push -q origin HEAD "v$v"
echo "released v$v"

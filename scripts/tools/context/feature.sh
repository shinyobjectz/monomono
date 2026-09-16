#!/usr/bin/env bash
# Feature lifecycle: Gherkin first, a red test target second, implementation third.
# A feature is context/projects/<project>/features/<slug>/{feature.md,bdd/,test/,BUCK}.
# Tests are buck2 targets, so `just test //context/...` is the lock.

source "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  just context feature new <project> <slug>
  just context feature list [project]
  just context feature status <project> <slug>
  just context feature check [project [slug]]
  just context feature test <project> <slug> <name>
USAGE
  exit 2
}

is_feature() { [[ -d $1/bdd && -d $1/test && -f $1/feature.md ]]; }
is_project() { [[ -f $1/PROJECT.md && -d $1/features ]]; }
feature_dir() { printf '%s/%s/features/%s' "$MONO_PROJECTS" "$1" "$2"; }

iter_features() {
  local project=${1-} pdir fdir
  for pdir in "$MONO_PROJECTS"/*/; do
    [[ -d $pdir/features ]] || continue
    [[ -z $project || $(basename "$pdir") == "$project" ]] || continue
    for fdir in "$pdir"features/*/; do
      is_feature "$fdir" || continue
      echo "$(basename "$pdir")/$(basename "$fdir")"
    done
  done
}

gherkin_files() { find "$1/bdd" -type f -name '*.feature' 2>/dev/null | sort; }
test_files() { find "$1/test" -type f ! -name '.gitkeep' 2>/dev/null | sort; }
count() { [[ -n ${1-} ]] && printf '%s\n' "$1" | grep -c . || echo 0; }

stage_for() {
  if [[ $(count "$(gherkin_files "$1")") -eq 0 ]]; then echo spec
  elif [[ $(count "$(test_files "$1")") -eq 0 ]]; then echo test
  else echo implement; fi
}

next_for() {
  case "$1" in
    spec) echo "write Gherkin in bdd/*.feature" ;;
    test) echo "add a red test: just context feature test <project> <slug> <name>" ;;
    implement) echo "implement in library/ or app/ until just test //context/... is green" ;;
  esac
}

cmd_new() {
  local project=${1-} slug=${2-}
  [[ -n $project && -n $slug ]] || usage
  is_slug "$project" || die "project must be kebab-case: $project"
  is_slug "$slug" || die "slug must be kebab-case: $slug"
  is_project "$MONO_PROJECTS/$project" || die "unknown project: $project (just context project new $project)"
  local dest; dest=$(feature_dir "$project" "$slug")
  [[ ! -e $dest ]] || die "feature already exists: $project/$slug"
  mkdir -p "$dest/bdd" "$dest/test"
  touch "$dest/test/.gitkeep"
  local title; title=$(echo "$slug" | tr '-' ' ')
  cat >"$dest/feature.md" <<MD
---
name: ${slug}
title: ${title}
status: spec
description: Use when implementing or changing the ${title} feature.
summary:
implements: []
do: []
dont: []
---

# ${title}

Authored context only. Gherkin in \`bdd/\` is the spec. Keep this file under 200 lines.
MD
  cat >"$dest/bdd/${slug}.feature" <<GH
Feature: ${title}

  Scenario: first behavior
    Given a precondition
    When an action happens
    Then an observable outcome
GH
  cat >"$dest/BUCK" <<BUCK
# Feature tests. Each red test is a target; \`just test //context/...\` locks the spec.
load("@monomono//rules:defs.bzl", "mono_feature_tests")

mono_feature_tests(
    name = "${slug}",
    tests = glob(["test/*.sh"]),
)
BUCK
  echo "created $(rel "$dest")  stage=spec"
  echo "next: rewrite feature.md and bdd/${slug}.feature, then just context feature test $project $slug <name>"
}

cmd_list() {
  printf '%s\t%s\t%s\t%s\n' feature stage gherkin tests
  local spec dir
  while read -r spec; do
    [[ -n $spec ]] || continue
    dir=$(feature_dir "${spec%%/*}" "${spec#*/}")
    printf '%s\t%s\t%s\t%s\n' "$spec" "$(stage_for "$dir")" "$(count "$(gherkin_files "$dir")")" "$(count "$(test_files "$dir")")"
  done < <(iter_features "${1-}" | sort)
}

cmd_status() {
  local project=${1-} slug=${2-}
  [[ -n $project && -n $slug ]] || { cmd_list "$project"; return; }
  local dir; dir=$(feature_dir "$project" "$slug")
  is_feature "$dir" || die "unknown feature: $project/$slug"
  local stage; stage=$(stage_for "$dir")
  echo "feature   $project/$slug"
  echo "path      $(rel "$dir")"
  echo "stage     $stage"
  echo "next      $(next_for "$stage")"
  echo "bdd";  gherkin_files "$dir" | sed "s#^$MONO_ROOT/#  #"
  echo "test"; test_files "$dir" | sed "s#^$MONO_ROOT/#  #"
}

check_file() {
  local f=$1 err=0
  grep -qE '^[[:space:]]*Feature:' "$f" || { echo "missing Feature:  $(rel "$f")" >&2; err=1; }
  grep -qE '^[[:space:]]*Scenario( Outline)?:' "$f" || { echo "missing Scenario: $(rel "$f")" >&2; err=1; }
  return $err
}

cmd_check() {
  local project=${1-} slug=${2-} failed=0 spec dir f
  local specs=()
  if [[ -n $slug ]]; then specs=("$project/$slug"); else
    while read -r spec; do [[ -n $spec ]] && specs+=("$spec"); done < <(iter_features "$project")
  fi
  python3 "$MONO_HOME/scripts/update/skills.py" --root "$MONO_ROOT" --check || failed=1
  for spec in "${specs[@]+"${specs[@]}"}"; do
    dir=$(feature_dir "${spec%%/*}" "${spec#*/}")
    is_feature "$dir" || { echo "unknown feature: $spec" >&2; failed=1; continue; }
    if [[ $(count "$(gherkin_files "$dir")") -eq 0 ]]; then
      echo "no .feature files  $(rel "$dir")/bdd" >&2; failed=1; continue
    fi
    while read -r f; do [[ -n $f ]] && { check_file "$f" || failed=1; }; done < <(gherkin_files "$dir")
  done
  [[ $failed -eq 0 ]] || exit 1
  echo "gherkin ok (${#specs[@]} feature(s))"
}

cmd_test() {
  local project=${1-} slug=${2-} name=${3-}
  [[ -n $project && -n $slug && -n $name ]] || usage
  local dir; dir=$(feature_dir "$project" "$slug")
  is_feature "$dir" || die "unknown feature: $project/$slug"
  [[ $(count "$(gherkin_files "$dir")") -gt 0 ]] || die "write Gherkin before tests: $project/$slug"
  local base dest
  base=$(kebab "$name")
  dest="$dir/test/$base.sh"
  [[ ! -e $dest ]] || die "test already exists: $(rel "$dest")"
  cat >"$dest" <<SH
#!/usr/bin/env bash
# Red on purpose. Locks: $(rel "$dir")/bdd
# Replace the body with a real check, or swap this target for your language's test rule in ../BUCK.
set -euo pipefail
echo "red: ${project}/${slug} / ${name}" >&2
exit 1
SH
  chmod +x "$dest"
  rm -f "$dir/test/.gitkeep"
  echo "created $(rel "$dest")  stage=implement"
  echo "run: just test //$(rel "$dir"):${slug}"
}

action=${1:-list}
shift || true
case "$action" in
  new) cmd_new "$@" ;;
  list) cmd_list "$@" ;;
  status) cmd_status "$@" ;;
  check) cmd_check "$@" ;;
  test) cmd_test "$@" ;;
  *) usage ;;
esac

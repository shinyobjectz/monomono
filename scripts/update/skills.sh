#!/usr/bin/env bash
# Generate .agents/skills from PROJECT.md, feature.md, Gherkin, and library.md. Bash and awk only.
# Generated folders carry a `.generated` marker and are rewritten on every sync.
# Folders without the marker are hand-authored and left alone.
#
#   skills.sh [--root <dir>] [--check]

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

GENERATED=".generated"
MAX_LINES=200
DONT="Don't"
CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) MONO_ROOT=$2; shift 2 ;;
    --check) CHECK=1; shift ;;
    *) die "usage: skills.sh [--root dir] [--check]" ;;
  esac
done
SKILLS="$MONO_ROOT/.agents/skills"
PROJECTS="$MONO_ROOT/context/projects"
LIBRARY="$MONO_ROOT/library"

# ---- front matter -----------------------------------------------------------

# fm_get <file> <key>  — scalar value; quotes stripped; empty for lists or missing
fm_get() {
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && $0 ~ "^" k ":" {
      v = $0; sub("^" k ":[ \t]*", "", v); gsub(/^["'\'']|["'\'']$/, "", v)
      if (v != "[]") print v
      exit
    }
  ' "$1"
}

# fm_list <file> <key>  — one item per line from "key:\n  - item" blocks
fm_list() {
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && $0 ~ "^" k ":" { on = 1; next }
    on && $0 ~ /^[ \t]+-[ \t]/ { v = $0; sub(/^[ \t]+-[ \t]+/, "", v); gsub(/^["'\'']|["'\'']$/, "", v); print v; next }
    on { on = 0 }
  ' "$1"
}

# fm_body <file>  — everything after the closing ---
fm_body() {
  awk '
    NR == 1 && $0 != "---" { print; body = 1; next }
    body { print; next }
    NR > 1 && $0 == "---" { body = 1; next }
  ' "$1" | sed '/./,$!d'
}

bullets() {
  while IFS= read -r line; do [[ -n $line ]] && echo "- $line"; done
}

section_list() {
  local title=$1 file=$2 key=$3 items
  items=$(fm_list "$file" "$key" | bullets)
  [[ -n $items ]] && printf '## %s\n\n%s\n\n' "$title" "$items"
  return 0
}

# ---- gherkin ----------------------------------------------------------------

scenarios_md() {
  local f
  for f in "$1"/bdd/*.feature; do
    [[ -f $f ]] || continue
    awk '
      /^[ \t]*Scenario( Outline)?:/ { t = $0; sub(/^[ \t]*Scenario( Outline)?:[ \t]*/, "", t); if (open) print ""; print "### " t "\n"; open = 1; next }
      open && /^[ \t]*(Given|When|Then|And|But)[ \t]/ { s = $0; sub(/^[ \t]+/, "", s); print "- " s }
      END { if (open) print "" }
    ' "$f"
  done
}

# ---- writers ----------------------------------------------------------------

write_generated() {
  local dest=$1 content=$2
  if [[ -d $dest && ! -f $dest/$GENERATED ]]; then
    echo "skip hand-authored $(rel "$dest")" >&2
    return 0
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  echo "written by just agents sync; do not edit" >"$dest/$GENERATED"
  printf '%s\n' "$content" >"$dest/SKILL.md"
}

feature_skill() {
  local project=$1 slug=$2 dir=$3 fm="$3/feature.md"
  local title desc status summary body tests scen
  title=$(fm_get "$fm" title); [[ -n $title ]] || title=$slug
  desc=$(fm_get "$fm" description); [[ -n $desc ]] || desc="Use when working on the $slug feature of $project."
  status=$(fm_get "$fm" status); [[ -n $status ]] || status=spec
  summary=$(fm_get "$fm" summary)
  {
    printf -- '---\nname: %s-%s\ndescription: %s\n---\n\n# %s\n\n' "$project" "$slug" "$desc" "$title"
    printf 'Spec: `%s/bdd`. Status: %s.\n\n' "$(rel "$dir")" "$status"
    [[ -n $summary ]] && printf '%s\n\n' "$summary"
    section_list "Do" "$fm" do
    section_list "$DONT" "$fm" dont
    section_list "Implements" "$fm" implements
    scen=$(scenarios_md "$dir")
    [[ -n $scen ]] && printf '## Scenarios\n\n%s\n\n' "$scen"
    tests=$(find "$dir/test" -type f ! -name .gitkeep 2>/dev/null | sort | xargs -I{} basename {} | bullets)
    [[ -n $tests ]] && printf '## Tests\n\n%s\n\n' "$tests"
    body=$(fm_body "$fm")
    [[ -n $body ]] && printf '## Context\n\n%s\n' "$body"
  } | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

library_skill() {
  local domain=$1 dir=$2 lm="$2/library.md"
  local title desc summary body bucks
  title=$(fm_get "$lm" title); [[ -n $title ]] || title=$domain
  desc=$(fm_get "$lm" description); [[ -n $desc ]] || desc="Use when changing library/$domain."
  summary=$(fm_get "$lm" summary)
  {
    printf -- '---\nname: library-%s\ndescription: %s\n---\n\n# %s\n\n' "$domain" "$desc" "$title"
    printf 'Source: `%s`.\n\n' "$(rel "$dir")"
    [[ -n $summary ]] && printf '%s\n\n' "$summary"
    section_list "Do" "$lm" do
    section_list "$DONT" "$lm" dont
    bucks=$(find "$dir" -name BUCK -type f 2>/dev/null | sort | sed "s#^$dir/##" | bullets)
    [[ -n $bucks ]] && printf '## Targets\n\n%s\n\n' "$bucks"
    body=$(fm_body "$lm")
    [[ -n $body ]] && printf '## Context\n\n%s\n' "$body"
  } | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

# ---- check ------------------------------------------------------------------

check() {
  local errors=0 f n key dir
  while IFS= read -r f; do
    [[ -n $f ]] || continue
    n=$(wc -l <"$f" | tr -d ' ')
    if [[ $n -gt $MAX_LINES ]]; then echo "$(rel "$f"): $n lines (max $MAX_LINES)" >&2; errors=$((errors + 1)); fi
    for key in name description; do
      [[ -n $(fm_get "$f" "$key") ]] || { echo "$(rel "$f"): front matter needs $key" >&2; errors=$((errors + 1)); }
    done
  done < <({ find "$PROJECTS" -mindepth 2 -maxdepth 2 -name PROJECT.md; find "$PROJECTS" -mindepth 4 -maxdepth 4 -name feature.md; find "$LIBRARY" -mindepth 2 -maxdepth 2 -name library.md; } 2>/dev/null | sort)
  while IFS= read -r dir; do
    [[ -n $dir && -f $dir/feature.md ]] || continue
    if ! ls "$dir"/bdd/*.feature >/dev/null 2>&1; then
      echo "$(rel "$dir")/bdd: no .feature files" >&2; errors=$((errors + 1)); continue
    fi
    for f in "$dir"/bdd/*.feature; do
      grep -qE '^[[:space:]]*Feature:' "$f" || { echo "$(rel "$f"): missing Feature:" >&2; errors=$((errors + 1)); }
      grep -qE '^[[:space:]]*Scenario( Outline)?:' "$f" || { echo "$(rel "$f"): missing Scenario:" >&2; errors=$((errors + 1)); }
    done
  done < <(find "$PROJECTS" -mindepth 3 -maxdepth 3 -type d -path '*/features/*' 2>/dev/null | sort)
  if [[ $errors -eq 0 ]]; then echo "skills check ok" >&2; else echo "skills check: $errors problem(s)" >&2; fi
  return $((errors > 0))
}

# ---- generate ---------------------------------------------------------------

generate() {
  mkdir -p "$SKILLS"
  local tree=() wanted=() pdir fdir ldir project slug dest marker d hand
  if [[ -d $PROJECTS ]]; then
    for pdir in "$PROJECTS"/*/; do
      [[ -f $pdir/PROJECT.md ]] || continue
      project=$(basename "$pdir")
      for fdir in "$pdir"features/*/; do
        [[ -f $fdir/feature.md ]] || continue
        slug=$(basename "$fdir")
        dest="$SKILLS/features/$project/$slug"
        write_generated "$dest" "$(feature_skill "$project" "$slug" "${fdir%/}")"
        wanted+=("$dest"); tree+=("features/$project/$slug")
      done
    done
  fi
  if [[ -d $LIBRARY ]]; then
    for ldir in "$LIBRARY"/*/; do
      [[ -f $ldir/library.md ]] || continue
      dest="$SKILLS/library/$(basename "$ldir")"
      write_generated "$dest" "$(library_skill "$(basename "$ldir")" "${ldir%/}")"
      wanted+=("$dest"); tree+=("library/$(basename "$ldir")")
    done
  fi
  # prune stale generated folders and empty groups
  while IFS= read -r marker; do
    [[ -n $marker ]] || continue
    d=$(dirname "$marker")
    local keep=0 w
    for w in "${wanted[@]+"${wanted[@]}"}"; do [[ $w == "$d" ]] && keep=1; done
    [[ $keep -eq 1 ]] || rm -rf "$d"
  done < <(find "$SKILLS" -name "$GENERATED" 2>/dev/null)
  find "$SKILLS/features" "$SKILLS/library" -type d -empty -delete 2>/dev/null || true

  hand=$(find "$SKILLS" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | sort | while IFS= read -r s; do
    [[ -f $(dirname "$s")/$GENERATED ]] || echo "- \`$(basename "$(dirname "$s")")/\`"
  done)
  {
    echo "# Skills"
    echo
    echo "Generated by \`just agents sync\` from \`PROJECT.md\`, \`feature.md\`, Gherkin, and \`library.md\`. A \`.generated\` marker means the folder is rewritten on sync; edit the source instead. Folders without the marker are hand-authored procedures and are left alone."
    echo
    echo "| Working on | Open |"
    echo "| --- | --- |"
    echo "| a project feature | \`features/<project>/<slug>\` |"
    echo "| a library domain | \`library/<domain>\` |"
    echo "| a working procedure | the hand-authored skill folder |"
    if [[ -n $hand ]]; then echo; echo "## Procedures"; echo; echo "$hand"; fi
    if [[ ${#tree[@]} -gt 0 ]]; then echo; echo "## Generated"; echo; printf -- '- `%s/`\n' "${tree[@]}"; fi
  } >"$SKILLS/AGENTS.md"
  echo "skills: ${#tree[@]} generated, $(echo "$hand" | grep -c . || true) hand-authored"
}

if [[ $CHECK -eq 1 ]]; then check; else generate; fi

#!/usr/bin/env bash
# Junk drawer: volumes + records in context/dump/context.sqlite. Structured rows, not prose files.

source "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"

SCHEMA="$MONO_HOME/scripts/tools/context/schema.sql"
DEFAULT_VOLUMES=(
  "decisions|Choices we intend to keep"
  "notes|Working thoughts that are not a feature spec"
  "scrapes|Captured pages, quotes, and dumps"
  "vendor|Third-party quirks, API indexes, SDK notes"
  "toolchain|Host and language toolchain notes"
  "mistakes|Agent or human errors worth not repeating"
  "pointers|Notes that hardened into a feature"
)

require_cmd sqlite3

db_init() {
  mkdir -p "$(dirname "$MONO_CONTEXT_DB")"
  [[ -s $MONO_CONTEXT_DB ]] || rm -f "$MONO_CONTEXT_DB"
  mono_sqlite "$MONO_CONTEXT_DB" <"$SCHEMA"
  local row name desc
  for row in "${DEFAULT_VOLUMES[@]}"; do
    name=${row%%|*}; desc=${row#*|}
    mono_sqlite "$MONO_CONTEXT_DB" \
      "INSERT OR IGNORE INTO volumes(name, description, created_at) VALUES('$(sql_quote "$name")','$(sql_quote "$desc")','$(mono_now)');"
  done
}

ensure_volume() {
  local name=$1 desc=${2-}
  is_slug "$name" || die "volume must be a kebab-case slug: $name"
  db_init
  mono_sqlite "$MONO_CONTEXT_DB" \
    "INSERT OR IGNORE INTO volumes(name, description, created_at) VALUES('$(sql_quote "$name")','$(sql_quote "$desc")','$(mono_now)');"
}

usage() {
  cat >&2 <<'USAGE'
usage:
  just context put <volume> [--title t] [--tags t] [--source t] [body...]
  just context get [query|volume|id]
  just context volumes
  just context volume add <name> [description...]
USAGE
  exit 2
}

cmd_status() {
  db_init
  echo "db        $(rel "$MONO_CONTEXT_DB")"
  echo "volumes   $(mono_sqlite "$MONO_CONTEXT_DB" "SELECT count(*) FROM volumes;")"
  echo "records   $(mono_sqlite "$MONO_CONTEXT_DB" "SELECT count(*) FROM records;")"
  mono_sqlite "$MONO_CONTEXT_DB" -separator $'\t' \
    "SELECT name, (SELECT count(*) FROM records r WHERE r.volume = v.name), description FROM volumes v ORDER BY name;" \
    | awk -F'\t' '{printf "  %-12s %s  %s\n", $1, $2, $3}'
}

cmd_put() {
  local volume=${1-}
  [[ -n $volume ]] || usage
  shift
  local title="" tags="" source="" body="" id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title=$2; shift 2 ;;
      --tags) tags=$2; shift 2 ;;
      --source) source=$2; shift 2 ;;
      --id) id=$2; shift 2 ;;
      --) shift; break ;;
      -*) die "unknown flag: $1" ;;
      *) break ;;
    esac
  done
  if [[ $# -gt 0 ]]; then body="$*"; elif [[ ! -t 0 ]]; then body=$(cat); fi
  [[ -n $body || -n $title ]] || die "put needs a title, a body, or stdin"
  [[ -n $title ]] || title=$(printf '%s' "$body" | head -n 1 | cut -c1-80)
  [[ -n $id ]] || id=$(mono_id)
  ensure_volume "$volume"
  local now; now=$(mono_now)
  mono_sqlite "$MONO_CONTEXT_DB" \
    "INSERT INTO records(id, volume, title, body, tags, source, created_at, updated_at)
     VALUES('$(sql_quote "$id")','$(sql_quote "$volume")','$(sql_quote "$title")','$(sql_quote "$body")','$(sql_quote "$tags")','$(sql_quote "$source")','$now','$now');"
  printf '%s\t%s\t%s\n' "$id" "$volume" "$title"
}

cmd_get() {
  db_init
  local q=${1-}
  if [[ -z $q ]]; then
    mono_sqlite "$MONO_CONTEXT_DB" -separator $'\t' "SELECT id, volume, title, created_at FROM records ORDER BY created_at DESC LIMIT 20;"
    return
  fi
  if [[ $(mono_sqlite "$MONO_CONTEXT_DB" "SELECT count(*) FROM records WHERE id='$(sql_quote "$q")';") == 1 ]]; then
    mono_sqlite "$MONO_CONTEXT_DB" -separator $'\t' "SELECT id, volume, title, tags, source, created_at, body FROM records WHERE id='$(sql_quote "$q")';"
    return
  fi
  if [[ $(mono_sqlite "$MONO_CONTEXT_DB" "SELECT count(*) FROM volumes WHERE name='$(sql_quote "$q")';") == 1 ]]; then
    mono_sqlite "$MONO_CONTEXT_DB" -separator $'\t' "SELECT id, volume, title, created_at FROM records WHERE volume='$(sql_quote "$q")' ORDER BY created_at DESC;"
    return
  fi
  local like; like=$(sql_quote "%$q%")
  mono_sqlite "$MONO_CONTEXT_DB" -separator $'\t' \
    "SELECT id, volume, title, created_at FROM records WHERE title LIKE '$like' OR body LIKE '$like' OR tags LIKE '$like' ORDER BY created_at DESC LIMIT 50;"
}

action=${1:-status}
shift || true
case "$action" in
  status) cmd_status ;;
  put) cmd_put "$@" ;;
  get) cmd_get "$@" ;;
  volumes) db_init; mono_sqlite "$MONO_CONTEXT_DB" -separator $'\t' "SELECT name, description, created_at FROM volumes ORDER BY name;" ;;
  volume) [[ ${1-} == add && -n ${2-} ]] || usage; ensure_volume "$2" "${*:3}"; echo "volume $2" ;;
  init) db_init ;;
  *) usage ;;
esac

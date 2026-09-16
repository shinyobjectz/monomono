#!/usr/bin/env bash
# Dispatcher for the junk drawer, projects, and Gherkin features.

source "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"

HERE="$MONO_HOME/scripts/tools/context"

usage() {
  cat >&2 <<'USAGE'
usage:
  just context
  just context put <volume> [--title t] [--tags t] [--source t] [body...]
  just context get [query|volume|id]
  just context volumes
  just context volume add <name> [description...]
  just context project new <slug>
  just context project list
  just context feature new <project> <slug>
  just context feature list|status|check [project [slug]]
  just context feature test <project> <slug> <name>
USAGE
  exit 2
}

action=${1:-status}
shift || true
case "$action" in
  status)
    "$HERE/db.sh" status
    echo
    echo "features"
    "$HERE/feature.sh" list | awk 'NR==1 {next} {print "  " $0}'
    ;;
  put|get|volumes|volume|init) "$HERE/db.sh" "$action" "$@" ;;
  feature|features) "$HERE/feature.sh" "$@" ;;
  project|projects) "$HERE/project.sh" "$@" ;;
  -h|--help) usage ;;
  *) usage ;;
esac

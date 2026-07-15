#!/usr/bin/env bash
# Run the upstream Chatwoot production compose with local operational overrides.
#
#   ./up.sh              -> docker compose ... up -d
#   ./up.sh ps           -> any other compose subcommand
#   ./up.sh migrate      -> one-off database preparation (required before first up)
#
# The Chatwoot checkout (and its .env) stays the compose project directory,
# so container names, volumes, and env resolution are unchanged.
set -euo pipefail

CHATWOOT_DIR="${CHATWOOT_DIR:-$HOME/playground/chatwoot}"
HERE="$(cd "$(dirname "$0")" && pwd)"

compose() {
  docker compose \
    --project-directory "$CHATWOOT_DIR" \
    -f "$CHATWOOT_DIR/docker-compose.production.yaml" \
    -f "$HERE/docker-compose.override.yaml" \
    "$@"
}

if [ $# -eq 0 ]; then
  compose up -d
elif [ "$1" = "migrate" ]; then
  compose run --rm rails bundle exec rails db:chatwoot_prepare
else
  compose "$@"
fi

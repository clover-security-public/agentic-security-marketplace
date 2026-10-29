#!/usr/bin/env bash
#
# Clover Copilot plugin — credential setup.
#
# Copilot has no prompted plugin options, so the client id and secret are
# collected here and written to <plugin data dir>/env.sh, which run-hook.sh
# sources.
#
#   copilot/scripts/configure.sh [<plugin data dir>]             (interactive)
#   CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=… CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=… \
#     copilot/scripts/configure.sh [<plugin data dir>] --from-env
#
# A marketplace install keeps the tree at <home>/installed-plugins/<market>/<plugin>
# and its data at <home>/plugin-data/<market>/<plugin>, so there the data dir is
# derived and the documented command takes no argument. A direct install hashes
# its data dir, so it must be passed; the setup notice Copilot shows on a
# session without credentials always prints it.
#
# The prompts, defaults and file format are Devin's: same four values, same
# env.sh. Both live in the one tree, so this reuses its configure.sh rather
# than keeping a copy.
set -euo pipefail

TREE="$(cd -P "$(dirname "$0")/../.." && pwd -P)"

DATA=""
case "${1:-}" in
  ""|--*) ;;
  *) DATA="$1"; shift ;;
esac
if [ -z "$DATA" ]; then
  plugin="$(basename "$TREE")"
  market="$(basename "$(dirname "$TREE")")"
  installed="$(dirname "$(dirname "$TREE")")"
  if [ "$(basename "$installed")" = "installed-plugins" ] && [ "$market" != "_direct" ]; then
    DATA="$(dirname "$installed")/plugin-data/${market}/${plugin}"
  else
    echo "usage: configure.sh <plugin data dir> [--from-env]" >&2
    echo "  (the data dir can only be derived for a marketplace install under installed-plugins/)" >&2
    exit 2
  fi
fi

echo "Configuring Clover for ${DATA}"
CLOVER_DEVIN_DATA="$DATA" exec bash "${TREE}/devin/scripts/configure.sh" "$@"

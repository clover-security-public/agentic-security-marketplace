#!/usr/bin/env bash
# Marketplace entries must carry the metadata a customer reviews before
# installing, and the components they declare must be exactly what the plugin
# ships.
#
# Why declare components at all: Claude Code renders the install screen's
# "Will install" list from the marketplace ENTRY — it has not cloned the plugin
# yet. Only Anthropic's own curated catalog gets that list resolved server-side
# (the same plugin listed in claude-community shows "Component summary not
# available for remote plugin" while its claude-plugins-official listing lists
# every skill), and the official catalog has no application process. For a
# self-hosted marketplace the entry is the only input, so declaring here is the
# only way a customer sees the hooks before installing.
#
# Why it has to match: where an entry and the plugin's own hooks.json both
# define hooks for an event, the ENTRY wins (verified on Claude Code 2.1.239,
# .240, .241 — one fire, the entry's command). A drifted entry would therefore
# change what actually runs as well as mislead the install screen. Byte-equality
# also means a future CLI that merges instead of overriding is a no-op for us.
#
# Run from the marketplace tree root: bash tests/marketplace-metadata.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

MANIFEST=".claude-plugin/marketplace.json"
FAILED=0

command -v jq >/dev/null || { echo "marketplace-metadata.sh: jq is required" >&2; exit 2; }

# The clover plugin is the repo root, so its hooks file sits under claude/;
# every other plugin owns its own directory.
hooks_file_for() { case "$1" in clover) echo "claude/hooks/hooks.json" ;; *) echo "$1/hooks/hooks.json" ;; esac; }
plugin_root_for() { case "$1" in clover) echo "." ;; *) echo "$1" ;; esac; }

for name in $(jq -r '.plugins[].name' "$MANIFEST"); do
  entry=$(jq --arg name "$name" '.plugins[] | select(.name == $name)' "$MANIFEST")
  root=$(plugin_root_for "$name")
  hooks_file=$(hooks_file_for "$name")

  # --- metadata ---------------------------------------------------------------
  for field in displayName category homepage; do
    if [ -z "$(jq -r --arg f "$field" '.[$f] // ""' <<<"$entry")" ]; then
      echo "ERROR: $name: marketplace entry has no $field" >&2
      FAILED=1
    fi
  done

  # The clover plugin's homepage is its product documentation; the two MCP
  # plugins point at the marketplace README. USAGE.md still ships and is linked
  # from that README — it documents the clover plugin's hooks, so it must not
  # become another plugin's homepage.
  homepage=$(jq -r '.homepage // ""' <<<"$entry")
  case "$name:$homepage" in
    clover:https://docs.cloversec.io/*) ;;
    clover:*) echo "ERROR: clover's homepage must be its docs.cloversec.io product page (got $homepage)" >&2; FAILED=1 ;;
    *:*USAGE.md) echo "ERROR: $name must not point its homepage at USAGE.md — it documents the clover plugin's hooks" >&2; FAILED=1 ;;
  esac

  # --- hooks: declared, and identical to what the plugin ships -----------------
  if [ "$(jq -r 'has("hooks")' <<<"$entry")" != "true" ]; then
    echo "ERROR: $name: entry declares no \"hooks\" — the install screen would show no inventory. Mirror $hooks_file into the entry." >&2
    FAILED=1
  elif [ ! -f "$hooks_file" ]; then
    echo "ERROR: $name: entry declares hooks but $hooks_file does not exist" >&2
    FAILED=1
  else
    declared=$(jq -S '.hooks' <<<"$entry")
    shipped=$(jq -S '.hooks' "$hooks_file")
    if [ "$declared" != "$shipped" ]; then
      echo "ERROR: $name: entry hooks differ from $hooks_file — the entry wins at runtime, so this changes behaviour AND misleads the install screen" >&2
      diff <(echo "$shipped") <(echo "$declared") >&2 || true
      FAILED=1
    fi
  fi

  # --- skills: every declared path exists -------------------------------------
  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    if [ ! -f "$root/${skill#./}/SKILL.md" ]; then
      echo "ERROR: $name: declared skill $skill has no SKILL.md under $root" >&2
      FAILED=1
    fi
  done < <(jq -r '(.skills // []) | .[]' <<<"$entry")

  # --- mcpServers: declared inline, and identical to the plugin's own config ---
  # The entry names the server so the install screen can print it, and the
  # object has to equal claude-mcp.json's — the entry wins over both that file
  # and the root .mcp.json, and those three carrying the same server key under
  # the same URL is what keeps exactly one server registered (the interaction
  # validate.yml's shared-directory checks pin down).
  if [ -f "$root/claude-mcp.json" ]; then
    declared_mcp=$(jq -S '.mcpServers // empty' <<<"$entry")
    shipped_mcp=$(jq -S '.mcpServers' "$root/claude-mcp.json")
    if [ -z "$declared_mcp" ]; then
      echo "ERROR: $name: entry declares no \"mcpServers\" — mirror $root/claude-mcp.json into the entry" >&2
      FAILED=1
    elif [ "$declared_mcp" != "$shipped_mcp" ]; then
      echo "ERROR: $name: entry mcpServers differ from $root/claude-mcp.json — the entry wins at runtime" >&2
      diff <(echo "$shipped_mcp") <(echo "$declared_mcp") >&2 || true
      FAILED=1
    fi
  fi

  echo "OK: $name — metadata complete, hooks match $hooks_file"
done

# --- clover: Claude implementation review wiring, in the entry and hooks.json --
# session-baseline pins the diff the session starts from before the first turn,
# and stop-implementation-review polls and returns requirements as context the
# turn continues with — both sync, each with a timeout above its poll budget.
# snapshot-working-tree (before an edit tool or Bash) and mark-session-edit
# (after it, succeeded or failed) count the session's own edits, which gate the
# Stop's submit; all sync, so a mark lands before the Stop reads it.
# assert_hook <file> <jq path to the hooks object> <event> <subcommand> <timeout>
assert_hook() {
  local hook
  hook=$(jq -c --arg event "$3" --arg sub "$4" \
    "$2"' | .[$event] // [] | [.[].hooks[] | select(.command | endswith("run-hook.sh\" " + $sub))]' "$1")
  if [ "$(jq 'length' <<<"$hook")" != "1" ]; then
    echo "ERROR: $1: want exactly one $3 hook running $4, got $hook" >&2
    FAILED=1
  elif [ "$(jq --argjson timeout "$5" '.[0] | (has("async") | not) and .timeout == $timeout and .shell == "bash"' <<<"$hook")" != "true" ]; then
    echo "ERROR: $1: $3 $4 must be sync (no async), shell bash, timeout $5 — got $hook" >&2
    FAILED=1
  fi
}
# assert_matcher <file> <jq path to the hooks object> <event> <subcommand> <matcher>
assert_matcher() {
  local matchers
  matchers=$(jq -c --arg event "$3" --arg sub "$4" \
    "$2"' | .[$event] // [] | [.[] | select(any(.hooks[]; .command | endswith("run-hook.sh\" " + $sub))) | .matcher]' "$1")
  if [ "$matchers" != "$(jq -cn --arg m "$5" '[$m]')" ]; then
    echo "ERROR: $1: $3 $4 must match exactly \"$5\", got $matchers" >&2
    FAILED=1
  fi
}
for target in "claude/hooks/hooks.json:.hooks" "$MANIFEST:.plugins[] | select(.name == \"clover\") | .hooks"; do
  assert_hook "${target%%:*}" "${target#*:}" SessionStart session-baseline 15
  assert_hook "${target%%:*}" "${target#*:}" Stop stop-implementation-review 120
  # Only Bash is fingerprinted around the call; an edit tool's file is in its
  # payload, and a failed one changed nothing.
  for event_subcommand_matcher in "PreToolUse:snapshot-working-tree:Bash" \
    "PostToolUse:mark-session-edit:Edit|Write|MultiEdit|NotebookEdit|Bash" "PostToolUseFailure:mark-session-edit:Bash"; do
    IFS=: read -r event sub matcher <<<"$event_subcommand_matcher"
    assert_hook "${target%%:*}" "${target#*:}" "$event" "$sub" 15
    assert_matcher "${target%%:*}" "${target#*:}" "$event" "$sub" "$matcher"
  done
done

# --- devin: implementation review wiring, in both hook files -----------------
# A Devin plugin install loads the plugin-root hooks.json; a manual install
# under .devin/clover loads devin/hooks/hooks.v1.json. Both must carry every
# hook, with the same events, matchers and timeouts, differing only in root.
devin_hook_shape='[to_entries[] | .key as $event | .value[] | (.matcher // "") as $matcher | .hooks[] |
  {event: $event, matcher: $matcher, sub: (.command | split("\" ") | last), timeout: (.timeout // 0)}] | sort_by(.event, .sub)'
if [ "$(jq -c "$devin_hook_shape" hooks.json)" != "$(jq -c "$devin_hook_shape" devin/hooks/hooks.v1.json)" ]; then
  echo "ERROR: hooks.json and devin/hooks/hooks.v1.json register different Devin hooks" >&2
  FAILED=1
fi
devin_edit_tools="write|edit|apply_patch|notebook_edit|exec"
for event_and_subcommand in SessionStart:session-baseline:30: PreToolUse:snapshot-working-tree:30:exec \
  PostToolUse:mark-session-edit:30:$devin_edit_tools Stop:stop-implementation-review:120:; do
  IFS=: read -r event sub timeout matcher <<<"$event_and_subcommand"
  found=$(jq -c --arg event "$event" --arg sub "$sub" --argjson timeout "$timeout" --arg matcher "$matcher" \
    "$devin_hook_shape"' | map(select(.event == $event and .sub == $sub and .timeout == $timeout and .matcher == $matcher)) | length' hooks.json)
  if [ "$found" != "1" ]; then
    echo "ERROR: hooks.json: want one $event $sub hook (timeout $timeout, matcher \"$matcher\"), got $found" >&2
    FAILED=1
  fi
done

[ -f USAGE.md ] || { echo "ERROR: USAGE.md is missing — README.md links it" >&2; FAILED=1; }

exit "$FAILED"

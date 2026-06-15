#!/usr/bin/env bash
#
# Clover Cursor plugin — one-shot credential setup.
#
# Persists Clover API credentials to ~/.cursor/clover/env.sh (chmod 600). Both
# hooks read this file: setup.sh at sessionStart and run-hook.sh on every fire
# (it sources env.sh whenever CAS_CLOVER_PLUGIN_CLIENT_ID is empty). GUI-launched
# Cursor inherits no shell environment and Cursor has no native plugin-secret
# config, so this file IS the durable credential store — write it once and every
# future session is authenticated. No Cursor restart needed: the next hook fire
# sources it.
#
# Driven by the /clover-setup command, or run directly:
#   bash clover-setup.sh --client-id <id> --client-secret <secret> \
#        [--auth-url <url>] [--server-url <url>]
# Values may also arrive via the CAS_CLOVER_PLUGIN_* environment variables.
#
# Credentials are validated against the Frontegg token endpoint (the same
# client-credentials exchange the binary performs) before anything is written,
# so a typo fails loudly here instead of silently at the next plan review.
set -uo pipefail

DATA="${HOME}/.cursor/clover"
ENV_FILE="$DATA/env.sh"
TOKEN_CACHE="$DATA/token.json"

# Defaults match the current Clover production deployment. Override per-run with
# --auth-url / --server-url for other environments.
DEFAULT_AUTH_URL="https://auth.cloversec.io"
DEFAULT_SERVER_URL="https://api.cloversec.io"

CLIENT_ID="${CAS_CLOVER_PLUGIN_CLIENT_ID:-}"
CLIENT_SECRET="${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}"
AUTH_URL="${CAS_CLOVER_PLUGIN_AUTH_URL:-}"
SERVER_URL="${CAS_CLOVER_PLUGIN_SERVER_URL:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --client-id)     CLIENT_ID="${2:-}"; shift 2 ;;
    --client-secret) CLIENT_SECRET="${2:-}"; shift 2 ;;
    --auth-url)      AUTH_URL="${2:-}"; shift 2 ;;
    --server-url)    SERVER_URL="${2:-}"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "clover-setup: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
  echo "clover-setup: --client-id and --client-secret are required" >&2
  echo "clover-setup: get them from the Clover web app > Settings > API Tokens" >&2
  exit 2
fi

AUTH_URL="${AUTH_URL:-$DEFAULT_AUTH_URL}"
SERVER_URL="${SERVER_URL:-$DEFAULT_SERVER_URL}"
AUTH_URL="${AUTH_URL%/}"
SERVER_URL="${SERVER_URL%/}"

# Validate before persisting. A real auth rejection (got an HTTP response that
# is not 200) is a hard stop — the creds or auth URL are wrong, so writing them
# would only defer the failure. A non-response (curl missing, or status 000 from
# a network/proxy hiccup) is ambiguous, so we write anyway with a warning rather
# than block setup on something the user can't fix here.
status="000"
if command -v curl >/dev/null 2>&1; then
  # curl prints %{http_code} (000 when no response was received) and exits
  # non-zero on a connection/timeout failure — capture stdout only, swallow the
  # exit code, and normalize an empty result to 000.
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    --max-time 15 \
    -X POST "$AUTH_URL/identity/resources/auth/v1/api-token" \
    -H 'Content-Type: application/json' \
    -d "{\"clientId\":\"$CLIENT_ID\",\"secret\":\"$CLIENT_SECRET\"}" 2>/dev/null)"
  [ -z "$status" ] && status="000"
else
  echo "clover-setup: curl not found — skipping credential check, writing anyway." >&2
fi

if [ "$status" != "200" ] && [ "$status" != "000" ]; then
  echo "clover-setup: credential check FAILED — auth ${AUTH_URL} returned HTTP ${status}." >&2
  echo "clover-setup: verify the Client ID / Client Secret and --auth-url, then re-run. Nothing was written." >&2
  exit 1
fi

mkdir -p "$DATA"
{
  printf 'export CAS_CLOVER_PLUGIN_CLIENT_ID=%q\n'     "$CLIENT_ID"
  printf 'export CAS_CLOVER_PLUGIN_CLIENT_SECRET=%q\n' "$CLIENT_SECRET"
  printf 'export CAS_CLOVER_PLUGIN_AUTH_URL=%q\n'      "$AUTH_URL"
  printf 'export CAS_CLOVER_PLUGIN_SERVER_URL=%q\n'    "$SERVER_URL"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Drop any token cached under old or empty creds so the new ones take effect on
# the next hook fire without a Cursor restart.
rm -f "$TOKEN_CACHE" 2>/dev/null || true

if [ "$status" = "200" ]; then
  echo "clover-setup: credentials verified and saved to $ENV_FILE"
else
  echo "clover-setup: credentials saved to $ENV_FILE (could not reach $AUTH_URL to verify — they will be used as-is)"
fi
echo "clover-setup: setup is persistent — every future Cursor session is ready, no restart needed."

---
name: clover-setup
description: Configure Clover security credentials on this machine, once and persistently — no restart, no Claude Code required.
---

You are configuring Clover's coding-agent security credentials on this machine. Clover needs an API **Client ID** and **Client Secret** (from the Clover web app → **Settings → API Tokens**). Persisting them once sets up every future Cursor session — the hooks read the saved file on every run.

Follow these steps exactly.

## 1. Collect the credentials

- **Client ID** and **Client Secret** are required.
- If the user already provided them in their message (in any obvious form — `client_id: …`, `id=…`, a pasted pair, etc.), use those.
- Otherwise, ask the user to paste their **Client ID** and **Client Secret**, then wait for their reply.
- **Auth URL** and **Server URL** are optional. Leave them unset unless the user names a non-default Clover environment — the defaults below are correct for Clover production.

Never print the Client Secret back to the user, and never write it into a file other than the one below.

## 2. Persist and verify

Prefer the plugin's own setup script — it validates the credentials against Clover before saving and clears any stale token cache. Locate and run it:

```bash
SETUP="${CURSOR_PLUGIN_ROOT:-}/cursor/scripts/clover-setup.sh"
if [ ! -x "$SETUP" ]; then
  SETUP="$(ls -t "$HOME"/.cursor/plugins/cache/*/*/*/cursor/scripts/clover-setup.sh 2>/dev/null | head -1)"
fi
if [ -n "$SETUP" ] && [ -f "$SETUP" ]; then
  bash "$SETUP" --client-id '<CLIENT_ID>' --client-secret '<CLIENT_SECRET>'
  # add --auth-url '<URL>' --server-url '<URL>' only if the user named a non-default environment
fi
```

If the script cannot be found, fall back to writing the credential file directly (this does exactly what the script does — validate, write, clear the token cache):

```bash
CID='<CLIENT_ID>'; SEC='<CLIENT_SECRET>'
AUTH_URL='https://auth.cloversec.io'      # override only for a non-default environment
SERVER_URL='https://api.cloversec.io'
DATA="$HOME/.cursor/clover"
status=000
command -v curl >/dev/null 2>&1 && status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
  -X POST "${AUTH_URL%/}/identity/resources/auth/v1/api-token" -H 'Content-Type: application/json' \
  -d "{\"clientId\":\"$CID\",\"secret\":\"$SEC\"}" 2>/dev/null)"
[ -z "$status" ] && status=000
if [ "$status" != "200" ] && [ "$status" != "000" ]; then
  echo "FAILED: auth ${AUTH_URL} returned HTTP $status — check the Client ID/Secret/Auth URL. Nothing written."; exit 1
fi
mkdir -p "$DATA"
{ printf 'export CAS_CLOVER_PLUGIN_CLIENT_ID=%q\n' "$CID"
  printf 'export CAS_CLOVER_PLUGIN_CLIENT_SECRET=%q\n' "$SEC"
  printf 'export CAS_CLOVER_PLUGIN_AUTH_URL=%q\n' "${AUTH_URL%/}"
  printf 'export CAS_CLOVER_PLUGIN_SERVER_URL=%q\n' "${SERVER_URL%/}"; } > "$DATA/env.sh"
chmod 600 "$DATA/env.sh"
rm -f "$DATA/token.json" 2>/dev/null || true
echo "OK: credentials verified and saved to $DATA/env.sh"
```

## 3. Report the result

- On success: tell the user Clover is configured and will review every plan automatically from now on — no restart needed.
- On `FAILED`: tell them exactly what the check reported (wrong credentials or auth URL) and that they can re-run `/clover-setup` once corrected.
- Keep it to one or two lines. Do not echo the Client Secret.

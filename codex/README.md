# Clover for Codex

## Developer installation

Run the installer and enter the API client credentials from Clover Settings:

```bash
curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/codex/scripts/install.sh | bash
```

The installer adds the public marketplace and plugin, verifies the downloaded
binary checksum, stores credentials with mode `0600`, and writes an explicit
installation-verification event to Clover. Codex requires one final trust step
for an ordinary marketplace plugin: start Codex and, when it reports that four
hooks are new or changed, choose **Trust all and continue**. If the prompt does
not appear, run `/hooks` and confirm all four Clover hooks are active. A changed
hook definition is reviewed again because trust is bound to the definition
hash.

For non-interactive installation, set
`CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID` and
`CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET`. The same prefix supports
`SERVER_URL`, `AUTH_URL`, `USER_EMAIL`, `LOG_MAX_MB`, and `STATE_TTL_DAYS`.
Legacy `CAS_CLOVER_PLUGIN_*` variables remain supported, but the Kura-prefixed
form takes precedence.

## Beta validation

After the source release has reached the beta marketplace, install that channel
with:

```bash
curl -fsSL https://raw.githubusercontent.com/clover-security-public/clover-security-marketplace-beta/main/codex/scripts/install.sh | bash -s -- --beta
```

This installs `clover@clover-security-beta`. Do not enable the public and beta
plugins together because both copies would run the same hooks.

## Administrator-managed installation

On a machine without an existing `/etc/codex/requirements.toml`:

```bash
curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/codex/scripts/install.sh | bash -s -- --managed
```

This installs the verified runtime under `/opt/clover/codex` and defines the
hooks in `/etc/codex/requirements.toml`. Codex recognizes these as managed
hooks, so they are trusted by administrator policy and do not display the
per-user hook trust prompt.

For MDM, deploy these two payloads instead of executing the interactive path:

1. Install `bin/clover-hook` and `codex/managed/run-hook.sh` under the same
   absolute managed directory. Verify the binary with `bin/checksums.sha256`.
2. Render `codex/managed/requirements.toml.template` with that absolute path
   and merge it into the organization's managed `requirements.toml` profile.
3. Deliver each developer's `env.sh` through the organization's per-user secret
   mechanism with mode `0600`, then run `run-hook.sh codex-doctor` as that user.
4. Pilot the profile on a managed device, restart Codex, and open `/hooks`.
   Confirm the three Clover entries are labeled managed and active, with no
   per-user trust action. The repository test validates the rendered policy and
   installer layout; this device check validates that the deployed MDM profile
   reached Codex's active managed configuration layer.

Do not install the ordinary Clover marketplace plugin on the same managed
device: both hook sources would fire. The template intentionally does not set
`allow_managed_hooks_only`, because that organization-wide switch disables all
user, project, session, and plugin hooks—not only duplicate Clover hooks.

Managed binaries do not self-update. Re-deploy them through MDM so the binary,
checksum manifest, wrapper, and requirements remain one reviewed release.

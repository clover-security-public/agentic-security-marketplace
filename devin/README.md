# Clover for Devin

Brings Clover's silent plan review to **Devin** — the CLI ("Devin for Terminal")
and Devin Desktop, which run the same local agent and read the same config.
Installs through Devin's own plugin system and shares the `clover-hook` binary
and `bin/` tree with the Claude, Cursor and Kiro surfaces.

## Install

The plugin is the **marketplace tree root**, not the `devin/` subdirectory:

```bash
devin plugins install clover-security-public/agentic-security-marketplace -y

devin plugins info clover     # Hooks must list 4 entries
```

A plain install registers at the **account** (synced to your other devices and
cloud) and is *eventually consistent*: it can take a minute to materialise
locally, and until `devin plugins list` shows `clover`, sessions run without the
plugin. It also silently replaces a `--local` install of the same plugin.
`--local` installs immediately, on this machine only.

Then set credentials once (Clover Settings → API Tokens):

```bash
~/.devin/clover/configure.sh
```

Devin has **no equivalent of Claude's prompted `userConfig`** — verified: it
ignores a `userConfig`/`secrets` block in the manifest entirely, and surfaces no
config UI. So credentials are set by a script, and `setup.sh` copies it to that
stable path on first session so the command never depends on where the plugin
was installed.

Until it is configured, Clover reviews nothing. Devin surfaces neither hook
stderr nor an install prompt, so that state would otherwise be invisible: the
first prompt of each session injects a `UserPromptSubmit` `additionalContext`
notice telling the user to run the command above — once per session, not per
prompt.

> **Workspace trust is required.** Devin ignores project config *and hooks* in an
> untrusted workspace, silently. The first `devin` run in a repo prompts to trust
> it — answer yes, or no hook ever fires. `/hooks` lists what actually loaded.

### Why the tree root, and not `#devin`

`devin plugins install owner/repo#subdir` materialises **only that subdirectory**
in the plugin cache. A `#devin` install therefore has no `bin/` and no
`.claude-plugin/plugin.json` beside it, so `setup.sh` finds no bundled binary and
no channel — it deploys nothing, every hook fails open, and writes go ungated
while `devin plugins info` still lists three healthy hooks. Making the tree root
the plugin is what puts `bin/` and the channel manifest inside the install.

`marketplace/.devin-plugin/plugin.json` and `marketplace/hooks.json` are that
root plugin. There is deliberately no manifest under `devin/`, so a `#devin`
install fails outright instead of silently installing a gate that never fires.

### Devin Cloud sessions are not covered

Verified against a live cloud sandbox: the classic cloud VM has no CLI plugin
store and does not execute CLI plugin hooks. Work done in app.devin.ai cloud
sessions is therefore **not gated by this plugin** — coverage there comes from
the Devin API integration (`IntegrationType.Devin`), not hooks.

### Local validation

`scripts/local-install.sh` assembles the `clover-local` channel from the working
tree; install the Devin plugin from its root:

```bash
devin plugins install --local ~/.clover/local-marketplace -y
```

A local-path install symlinks to the source, so edits apply on the next session.

## Org rollout (the primary path for teams)

Individual `configure.sh` runs do not scale to a team. The rollout is two
fleet-managed pieces, both using only mechanisms verified against the real CLI:

**1. Install the plugin per developer** (their own machines):

```bash
devin plugins install clover-security-public/agentic-security-marketplace -y
```

**2. Distribute the credentials** as environment. The hooks read
`CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID`, `CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET`,
`CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL`, `CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL`
from, in order:

- **The environment of the process that launches `devin`** — verified: hooks
  inherit the launcher's env. Fleet-manage it like any other machine env:
  a managed shell-profile drop on macOS/Linux, user environment variables on
  Windows (the Windows path reads process env directly and does not source any
  file).
- **`~/.devin/clover/env.sh` (mode 600), POSIX only** — verified: the shim
  sources it when the env is empty. A one-file MDM/fleet drop per machine;
  `configure.sh` writes exactly this file for the manual case.

Use a per-team (or per-org) Clover API client, not a personal one, so rotation
is one secret in one place.

**What does NOT work** — all verified against Devin CLI 3000.6.2, so don't
burn time on them: a `userConfig`/`secrets` block in the plugin manifest
(ignored, no prompt), an `env` map on a hook entry (not injected), and an `env`
block in `.devin/config.json` (not injected). Devin's org "managed plugins"
scope exists in its config model but its admin-side setup is undocumented here —
if Devin's admin console can push plugins org-wide, step 1 collapses into it;
credentials still arrive per this section.

`CLOVER_DEVIN_ROOT` relocates the adapter to a fixed path if an org prefers to
lay the files down itself instead of using the plugin manager.

## How it maps to Devin

Devin's hooks are Claude-Code-compatible in shape but not vocabulary: tool names
are lowercase (`write`, `edit`, `exec`), `matcher` is a **regex over
`tool_name`**, and a block is `{"decision":"block","reason":…}` rather than
Claude's `hookSpecificOutput.permissionDecision`. The shim emits both dialects,
so a vocabulary change cannot silently turn the gate into a no-op.

| Devin event | Clover action | Claude equivalent |
|---|---|---|
| `SessionStart` | `setup` — deploy + verify binary | same |
| `UserPromptSubmit` | `log-prompt` — prompt audit | same |
| `PreToolUse` (`write\|edit\|apply_patch`) | `review-write` — plan gate | `Edit\|Write\|MultiEdit` → `should-review-plan` |
| — | n/a: no `ExitPlanMode` tool | `ExitPlanMode` → `review-plan` |
| — | not wired (see **Updates**) | `SessionStart` → `check-update` |

`apply_patch` is in the matcher because Devin writes files through it too. It
carries a patch rather than a path, so the target is recovered from the patch
header (`*** Update/Add File:`, or a unified diff's `+++ b/`); without that the
gate fires, finds no path, and allows — which reads exactly like a reviewed write.

Devin exports `DEVIN_PLUGIN_ROOT` (and `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PROJECT_DIR`)
to plugin hooks; `PLUGIN_ROOT` from the public docs is **not** set. Hook commands
resolve their root as
`${CLOVER_DEVIN_ROOT:-${DEVIN_PLUGIN_ROOT:-${DEVIN_PROJECT_DIR}/.devin/clover}}`,
so `CLOVER_DEVIN_ROOT` relocates the adapter for an org rollout without editing
the hooks file.

### Why the plan gate hangs off `.md` writes

Clover reviews *plan text*. Claude Code hands it over through the `ExitPlanMode`
tool input; Devin has no such tool, and its `/plan` approval is a UI action, not
a hook event. What Devin does expose is `PreToolUse` with a regex matcher, and
`write`/`edit` carry `file_path` + `content`.

That is the seam Claude Code's auto-mode already uses: intercept the `.md` write
and let the server classify whether the file is a plan (`should-review-plan`).
A plan the agent is about to commit to disk is reviewed before it lands; a
non-plan `.md` is waved through by the server's classifier; anything that is not
`.md` never leaves the shim.

## Provider equivalence

Devin's write/edit payloads were captured from a live session (Devin CLI
3000.6.2) and use the **same field names as Claude**:

| tool | `tool_input` |
|---|---|
| `write` | `file_path`, `content` |
| `edit` | `file_path`, `old_string`, `new_string` |

So both surfaces run the identical `resolveFileContent` reconstruction and send
the server the same text for the same change. `agent_devin_test.go` pins that
equivalence — a rename on either side fails the test rather than silently
changing what gets reviewed.

**The one real difference:** Claude has a second gate, `ExitPlanMode` →
`review-plan`, which reviews a plan the moment plan mode exits, even if it is
never written to disk. Devin has no `ExitPlanMode` tool and its `/plan` approval
is not a hook event, so on Devin a plan that is only discussed in chat and never
written to a `.md` is **not** reviewed. Anything written to a `.md` is gated
identically on both.

`apply_patch` is covered defensively: it is in the matcher and its header is
parsed for the target path, but Devin's model reached for `edit` in every
live capture, so that payload shape has not been observed in the wild.

## Windows

Every hook dispatches through `scripts/clover-hook.cmd`, a cmd/sh polyglot —
the same shape Cursor uses. Line 1 is a label to `cmd.exe` and an `exec` into
`setup.sh` / `run-hook.sh` for POSIX, so macOS and Linux behave exactly as if
the scripts were called directly.

On Windows there is no bash and no jq, so the batch half skips the shell
entirely and pipes the hook payload straight into the bundled `.exe`, which
speaks Devin's protocol natively through its `devin-setup`, `devin-log-prompt`
and `devin-review-write` subcommands (`cmd/clover-hook/agent_devin.go`). No hook
command names `bash` or a `.sh`, so nothing spawns a Git Bash console window on
every prompt. ARM64 falls back to the amd64 build, which Windows emulates.

`marketplace/tests/windows-support.sh` covers all of this.

## Updates

The plugin self-updates, like the Claude surface: a second `SessionStart` hook
(`check-update` → `devin-check-update`) compares the installed version against
the channel's marketplace manifest and, when behind, runs
`devin plugins update clover`. TTL-gated to once per 6h; fails open on any
error. Verified live: the update completes from inside a running session — the
hook binary runs from the data dir, so replacing the plugin cache never yanks
the running executable.

Devin has no marketplace autoUpdate, so the plugin's own check is the only
automatic path; the local channel (a symlinked working tree) is exempt. Manual
refresh is still `devin plugins update clover`.

## Binary and channels

`setup.sh` mirrors `claude/scripts/setup.sh`: it deploys the binary bundled in
the tree's `bin/`, **verified against `bin/checksums.sha256`**, and refuses to
deploy on a missing manifest or a mismatch. There is no polling auto-update —
updates arrive when the marketplace re-syncs the tree. A release download is a
public-channel-only fallback, also checksum-verified.

Version and channel come from the tree's `.claude-plugin/plugin.json`, which the
assembly and carry-forward scripts stamp per channel.
`devin/.devin-plugin/plugin.json` carries a **display-only** version that CI does
not stamp; reading it for the deploy decision would pin every channel to a stale
snapshot and skip the redeploy a new build needs.

`setup.sh` also refuses a binary lacking the **`should-review-plan`** subcommand:
an older build exits `Unknown command`, the shim fails open on every write, and
the gate is silently absent rather than visibly broken.

## Fail-open

Every hook path fails open: missing `jq`, a missing or unverifiable binary, auth
failure, an unparseable payload, or a server timeout all allow the write. The
gate blocks only on an explicit deny from the server.

## Debugging

- `CLOVER_DEBUG=1` — shim diagnostics on stderr.
- Binary log: `~/.devin/clover/.clover-hook.log`.
- `/hooks` inside Devin — shows which hooks loaded and from where.
- `hooks/discover.hooks.v1.json` — install as `.devin/hooks.v1.json` to log every
  event's full stdin payload to `/tmp/clover-devin-hook.log` and never block.
- `CLOVER_HOOK_BIN=/path/to/stub` — swap the binary to exercise the block path.

## Server side

`codingAgent: "Devin"` is already a member of the backend's `CodingAgentType`
enum (`Infrastructure/Entities/Enums/CodingAgentType.cs`), so review and audit
rows attribute correctly with no backend change.

# Clover for Devin

Brings Clover's silent plan review to **Devin** — the CLI ("Devin for Terminal")
and Devin Desktop, which run the same local agent and read the same config, and
app.devin.ai cloud sessions (see **Devin Cloud sessions**).
Installs through Devin's own plugin system and shares the `clover-hook` binary
and `bin/` tree with the Claude, Cursor and Kiro surfaces.

## Install

The plugin is the **marketplace tree root**, not the `devin/` subdirectory:

```bash
devin plugins install clover-security-public/agentic-security-marketplace -y

devin plugins info clover     # Hooks must list 5 entries
```

A plain install registers at the **account** (synced to your other devices and
cloud) and is *eventually consistent*: it can take a minute to materialise
locally, and until `devin plugins list` shows `clover`, sessions run without the
plugin. It also silently replaces a `--local` install of the same plugin.
`--local` installs immediately, on this machine only.

The beta ring installs from its own marketplace:

```bash
devin plugins install clover-security-public/clover-security-marketplace-beta -y
```

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
notice — once per session, not per prompt. A hook cannot tell a Devin cloud
session from a local one, so the notice names both fixes: the command above on
the developer's own machine, and, for cloud sessions, org secrets an admin
passes to the plugin through its manifest `env`, with a link to the setup docs.

> **Workspace trust is required.** Devin ignores project config *and hooks* in an
> untrusted workspace, silently. The first `devin` run in a repo prompts to trust
> it — answer yes, or no hook ever fires. `/hooks` lists what actually loaded.

### Why the tree root, and not `#devin`

`devin plugins install owner/repo#subdir` materialises **only that subdirectory**
in the plugin cache. A `#devin` install therefore has no `bin/` and no
`.claude-plugin/plugin.json` beside it, so `setup.sh` finds no bundled binary and
no channel — it deploys nothing, every hook fails open, and writes go ungated
while `devin plugins info` still lists five healthy hooks. Making the tree root
the plugin is what puts `bin/` and the channel manifest inside the install.

`marketplace/.devin-plugin/plugin.json` and `marketplace/hooks.json` are that
root plugin. There is deliberately no manifest under `devin/`, so a `#devin`
install fails outright instead of silently installing a gate that never fires.

### Devin Cloud sessions

Per Devin's plugin documentation, cloud sessions "fetch the enterprise,
organization, and personal manifests at start and install the resulting
plugins on the session machine"
([plugins](https://docs.devin.ai/product-guides/plugins)). They run `command`
hooks only, skipping `prompt` hooks
([plugins overview](https://docs.devin.ai/cli/extensibility/plugins/overview)),
and never fire `SessionEnd`. All five Clover hooks are `command` hooks on
`SessionStart`, `UserPromptSubmit`, `PreToolUse` and `PostToolUse`
(`marketplace/hooks.json`), so none is skipped. The cloud agent writes files
only through `exec`, which the **Exec gate** covers. A cloud `SessionStart` runs in the background and the agent
does not wait for it
([lifecycle hooks](https://docs.devin.ai/cli/extensibility/hooks/lifecycle-hooks)),
which is safe here: `run-hook.sh` deploys the binary itself when `setup` has not
finished. The session machine is Linux, so hooks go through `run-hook.sh` and
log to `~/.devin/clover/.clover-hook.log`.

An org admin sets it up once, with no developer machine involved:

1. Store the Clover `client_id` / `client_secret` as organization-level secrets
   (**Settings → Resources → Secrets**).
2. **Customize** → organization in the scope menu → **Plugins → Add plugin →
   From repository** → `clover-security-public/agentic-security-marketplace`
   (needs the **Manage plugins** organization permission).
3. **Plugin settings (gear) → Edit manifest**: give the entry an `env` block,
   which Devin documents as configuring command hooks in cloud sessions, that
   references the secrets and turns self-update off (see **Updates**):

   ```json
   {
     "source": "github",
     "repo": "clover-security-public/agentic-security-marketplace",
     "env": {
       "CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID": "secret:org:CLOVER_KURA_CLIENT_ID",
       "CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET": "secret:org:CLOVER_KURA_CLIENT_SECRET",
       "CLOVER_DEVIN_SELF_UPDATE": "off"
     }
   }
   ```

Changes apply from the next session; running sessions keep what they loaded at
start. The enterprise scope (`secret:enterprise:`) covers every org at once.

Each reference must name the scope its secret lives in. A `secret:personal:`
reference to a secret stored at org scope resolves to nothing, and Devin leaves
the variable unset in the hook process. The local Devin CLI applies the same
`env` block without resolving secrets, so the hooks receive the literal
`secret:...` string. The launcher and the binary treat such a value as unset, so
a developer machine that shares the manifest still reads `env.sh` from
`configure.sh`.

**Verified in live cloud sessions (2026-11-16, personal install, beta
channel):** the plugin installs a few seconds after the session starts;
`DEVIN_PLUGIN_ROOT` resolves, so `SessionStart` deployed the binary and ran the
update check; the machine has `jq` and bash; `UserPromptSubmit` fires and the
missing-credentials notice reaches the agent verbatim. Because the plugin loads
after the session starts, the **first prompt is not logged**. The agent has no
file-write tool and writes every file through `exec`, which is why the **Exec
gate** exists. On 0.1.109-beta.1 the gate was verified end to end up to the
review call: each `exec` starts from `$HOME`, a heredoc plan is intercepted
before the command runs at its real path, `PostToolUse` fires after every
command, a plan written by `python3` is caught as `md changed by exec`, and a
heredoc plan is not reviewed twice. Still open, because those sessions had no
Clover credentials and every review stopped at `auth failed`: whether the
manifest `env` reaches the hook process, and how a `PostToolUse` deny reaches
the agent (the restore itself is covered by `agent_devin_exec_test.go`). The Devin API integration (`IntegrationType.Devin`)
is separate: it reports usage (sessions, users, AI-written lines) and reviews no
plans. Customer-facing steps live in clover-docs, under *Connecting Kura To
Coding Agents → Devin → Cloud sessions*.

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
- **`~/.devin/clover/env.sh` (mode 600), POSIX only** — verified: the launcher
  sources it when the env is empty. A one-file MDM/fleet drop per machine;
  `configure.sh` writes exactly this file for the manual case.

Use a per-team (or per-org) Clover API client, not a personal one, so rotation
is one secret in one place.

**What does NOT work** — all verified against Devin CLI 3000.6.2, so don't
burn time on them: a `userConfig`/`secrets` block in the plugin manifest
(ignored, no prompt), an `env` map on a hook entry (not injected), and an `env`
block in `.devin/config.json` (not injected). The `env` block on a managed
manifest entry is a different mechanism: it is how credentials reach cloud
sessions (see **Devin Cloud sessions**).

An org admin can also install the plugin from **Customize** at organization or
enterprise scope instead of step 1. That covers the org's cloud sessions, and
the CLI and Desktop of members whose primary organization it is. Devin documents
the manifest `env` block for cloud sessions only, so local machines still take
their credentials from this section.

`CLOVER_DEVIN_ROOT` relocates the adapter to a fixed path if an org prefers to
lay the files down itself instead of using the plugin manager.

## How it maps to Devin

Devin's hooks are Claude-Code-compatible in shape but not vocabulary: tool names
are lowercase (`write`, `edit`, `exec`), `matcher` is a **regex over
`tool_name`**, and a block is `{"decision":"block","reason":…}` rather than
Claude's `hookSpecificOutput.permissionDecision`. The binary emits both
dialects, so a vocabulary change cannot silently turn the gate into a no-op.

Every hook runs the bundled binary's `devin-*` subcommands on every platform.
On macOS and Linux, `run-hook.sh` only deploys the binary if `SessionStart`
never ran, sources `env.sh` when the environment carries no credentials, and
pipes the payload through. It needs nothing but bash: no `jq`, so a machine
without it (a Devin cloud VM is not documented to ship it) still reviews plans.

| Devin event | Clover action | Claude equivalent |
|---|---|---|
| `SessionStart` | `setup` — deploy + verify binary | same |
| `UserPromptSubmit` | `log-prompt` — prompt audit | same |
| `PreToolUse` (`write\|edit\|apply_patch\|write_plan\|exec`) | `review-write` — plan gate | `Edit\|Write\|MultiEdit` → `should-review-plan` |
| `PostToolUse` (`exec`) | `review-exec` — plan gate for shell writes (see **Exec gate**) | — |
| — | n/a: the plan is reviewed at `write_plan` | `ExitPlanMode` → `review-plan` |
| `SessionStart` | `check-update` — self-update (see **Updates**) | same |

`apply_patch` is in the matcher because Devin writes files through it too, and
GPT-family models write every file with it. It carries a patch rather than the
file, so a patch in the Codex format (`*** Begin Patch`) is handed to the
binary's `devin-review-write`, which rebuilds each `.md` it writes with the
Codex gate's parser and reviews the result; without that the gate finds a path,
resolves no content, and allows — which reads exactly like a reviewed write.

`write_plan` is in the matcher because plan mode writes the plan with it, not
with `write`. Its `tool_input` is `{title, summary, plan}` and names no file:
Devin renders it into the session's plan file under `~/.devin/plans/` itself.
`devin-review-write` renders the same
Markdown (`# title`, the summary, then the plan) and reviews it as a `.md` write
to `~/.devin/plans/<session_id>.md`. That path is Clover's, not the file Devin
writes; it is stable per session, so each revision of the plan is judged
against the same review, and the requirements sidecar lands beside it. Without
this branch the gate finds no path and allows the plan unreviewed.

### Exec gate

Devin cloud has no file-write tool: a live cloud session reported it writes
every file, plans included, through its shell tool `exec`, so a gate on
`write`/`edit` alone never fires there. `exec` gets the same gate in two halves
(`cmd/clover-hook/agent_devin_exec.go`):

- **Before the command (`PreToolUse`).** A Markdown file written through a
  heredoc (`cat > PLAN.md <<'EOF'`, `cat <<EOF >> NOTES.md`, `tee [-a] F.md
  <<EOF`, `<<-` included) is rebuilt from the command and reviewed like any
  `.md` write. A deny blocks the command, so the plan never lands. An unquoted
  delimiter's expansions are not applied; the body is reviewed as written.
- **After the command (`PostToolUse`).** Any other write (python, `sed -i`,
  `cp`, `printf >`) cannot be read from the command, so `PreToolUse` first
  snapshots the workspace's Markdown: the repository the command runs in, or
  its directory outside one, skipping dot-directories and dependency and build
  folders. `review-exec` then reviews every new or changed file. A denied one is
  restored to its previous content, or removed if the command created it, and
  the reason goes back to the agent as a `PostToolUse` block with
  `additionalContext`. Heredoc writes already reviewed before the command are
  not reviewed twice.

Bounds: no snapshot past 2000 Markdown files or 8 MB, and files over 1 MB are
not tracked; such a workspace keeps only the heredoc half. A background command
(`run_in_background`) gets no snapshot, because it keeps writing after its
`PostToolUse`. Devin documents `command` in `exec`'s `tool_input` but no tool
use id, so a call's two halves pair on the command and its directory.

Where a command starts: an explicit `workdir`, otherwise the payload's
directory, except on a Devin cloud machine (`/opt/.devin` exists). A live cloud
session showed each `exec` call runs in a fresh shell that starts in `$HOME`
(`/home/ubuntu`) while the payload names `/home/ubuntu/repos`, so there the gate
starts from `$HOME`. A heredoc's relative path also follows any `cd` earlier in
the same command. A heredoc plan reviewed before the command is recognised by
its content afterwards, wherever its path resolved.

Devin exports `DEVIN_PLUGIN_ROOT` (and `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PROJECT_DIR`)
to plugin hooks; `PLUGIN_ROOT` from the public docs is **not** set. Hook commands
resolve their root as
`${CLOVER_DEVIN_ROOT:-${DEVIN_PLUGIN_ROOT:-${DEVIN_PROJECT_DIR}/.devin/clover}}`,
so `CLOVER_DEVIN_ROOT` relocates the adapter for an org rollout without editing
the hooks file.

### Why the plan gate hangs off `.md` writes

Clover reviews *plan text*. Claude Code hands it over through the `ExitPlanMode`
tool input. Devin's plan mode writes the plan with `write_plan` before its
approval, which is a UI action, not a hook event. What Devin does expose is
`PreToolUse` with a regex matcher: `write`/`edit` carry `file_path` + `content`,
and `write_plan` carries the plan itself.

That is the seam Claude Code's auto-mode already uses: intercept the `.md` write
and let the server classify whether the file is a plan (`should-review-plan`).
A plan the agent is about to commit to disk is reviewed before it lands; a
non-plan `.md` is waved through by the server's classifier; anything that is not
`.md` never leaves the binary.

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
never written to disk. Devin's `exit_plan_mode` is not gated: its plan mode
writes the plan with `write_plan` first, and that write is reviewed. A plan
that is only discussed in chat, never through `write_plan` or a `.md` write, is
**not** reviewed. Anything written to a `.md` is gated identically on both.

`write_plan`'s field names (`title`, `summary`, `plan`) come from the Devin CLI
3000.11.234 tool schema, not from a captured hook payload.

`apply_patch` is covered defensively: Devin's model reached for `edit` in every
live capture, so its payload shape has not been observed in the wild. The gate
reads the patch from `tool_input.patch`, `.diff` or `.input` and reconstructs it
the way the Codex gate does; a unified diff (`+++ b/`) yields a path but no
content, and is allowed.

## Windows

Every hook dispatches through `scripts/clover-hook.cmd`, a cmd/sh polyglot —
the same shape Cursor uses. Line 1 is a label to `cmd.exe` and an `exec` into
`setup.sh` / `run-hook.sh` for POSIX, so macOS and Linux behave exactly as if
the scripts were called directly.

On Windows there is no bash, so the batch half skips the shell entirely and
pipes the hook payload straight into the bundled `.exe`, which speaks Devin's
protocol natively through its `devin-setup`, `devin-log-prompt`,
`devin-review-write` and `devin-check-update` subcommands
(`cmd/clover-hook/agent_devin.go`) — the same ones `run-hook.sh` calls. No hook
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

`CLOVER_DEVIN_SELF_UPDATE=0` (or `false`/`off`/`no`) opts out, as
`CLOVER_CURSOR_SELF_UPDATE` and `CLOVER_CODEX_SELF_UPDATE` do for their
surfaces. Devin cloud sessions should set it: each one installs the plugin from
its managed manifest at start, so there is nothing to update. Set it in the
manifest entry's `env` block beside the credentials.

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

`setup.sh` also refuses a binary lacking the **`devin-review-write`** subcommand:
an older build exits `Unknown command`, the launcher fails open on every write,
and the gate is silently absent rather than visibly broken.

## Fail-open

Every hook path fails open: a missing or unverifiable binary, auth
failure, an unparseable payload, or a server timeout all allow the write. The
gate blocks only on an explicit deny from the server.

## Debugging

- `CLOVER_DEBUG=1` — launcher diagnostics on stderr.
- Binary log: `~/.devin/clover/.clover-hook.log`.
- `/hooks` inside Devin — shows which hooks loaded and from where.
- `hooks/discover.hooks.v1.json` — install as `.devin/hooks.v1.json` to log every
  event's full stdin payload to `/tmp/clover-devin-hook.log` and never block.
- `CLOVER_HOOK_BIN=/path/to/stub` — swap the binary to exercise the block path.

## Server side

`codingAgent: "Devin"` is already a member of the backend's `CodingAgentType`
enum (`Infrastructure/Entities/Enums/CodingAgentType.cs`), so review and audit
rows attribute correctly with no backend change.

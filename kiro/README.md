# Clover for Kiro

Clover security review inside [Kiro](https://kiro.dev), AWS's spec-driven
agentic IDE (and the Kiro CLI). Same binary and same `/Hooks/*` backend as the
Claude Code and Cursor surfaces — only the event plumbing differs, and it lives
in `cmd/clover-hook/agent_kiro.go`, not in these scripts.

## Why Kiro fits

Kiro writes its plan to disk as a **spec** —
`.kiro/specs/<feature>/{requirements,bugfix,design,tasks}.md`, or the whole spec
in a single `spec.md` in its newer single-file flow — and runs tasks
from it, firing a **blocking `PreTaskExec`** immediately before implementation.
That gives Clover a real plan artifact plus the closest analogue to Claude's
`ExitPlanMode` gate on any non-Claude agent.

| Trigger | Subcommand | Blocks |
|---|---|---|
| `UserPromptSubmit` | `kiro-log-prompt` | no |
| `PostFileSave` on `.kiro/specs/**/*.md` | `kiro-capture-spec` | no |
| `PreTaskExec` | `kiro-pre-task` | **yes** |

## The review loop

`PostFileSave` drives the loop and `PreTaskExec` enforces it:

1. Kiro finishes writing a spec. Capture reviews it and writes the security
   requirements Clover returns to `.kiro/steering/clover-requirements-<spec>.md`
   (`inclusion: always`), which Kiro includes in every subsequent interaction —
   alongside the `.clover-requirements.md` sidecar beside the spec. The
   developer's next prompt reprints them too, on `UserPromptSubmit`.
2. The agent folds them into the spec and saves. That save is a genuine revision,
   so capture sends it for judgement; Clover approves only when the requirements
   are actually covered — a cosmetic "we take security seriously" edit comes back
   denied with the musts still standing.
3. Starting a task re-reviews the spec and **blocks** while any must stands.

Capture reviews a spec only when it is **finished and settled**, and only one
review at a time per spec:

- **Finished** — the file Kiro writes last is present (`tasks.md`, or `spec.md`
  in the single-file spec flow).
- **Settled** — the spec content is unchanged across a short window
  (`CLOVER_KIRO_SPEC_SETTLE_SECONDS`, default 4), so the events for the earlier
  files of one generation drop out instead of each consuming a review round.
- **One at a time** — a lock file per spec directory, since two saves can settle
  together.

Those three guards are the fix for the surface's worst bug: capture used to
review on *every* save, so it reviewed half-written specs, and the next save of
the same generation arrived as a `JudgePlan` round — which tells the backend the
developer revised the plan to address the requirements. The approval that came
back deleted the requirements sidecar and recorded an approved-plan hash, which
then short-circuits the gate. Requirements found, silently discarded, gate off.

**Delivery channels are not interchangeable.** Kiro's own contract: `exit 0`
stdout is forwarded only for `SessionStart`, `UserPromptSubmit` and
`PreToolUse`; `exit 2` stderr is forwarded for `PreToolUse`,
`UserPromptSubmit` and `PreTaskExec`; anything else is a silent failure. A
`PostFileSave` hook therefore **cannot speak to the agent at all** — its stdout
is dropped on the floor. That is why a spec review delivers through steering and
the prompt channel, and why the gate's own verdict rides `exit 2` on
`PreTaskExec`.

Kiro's decision contract is the exit code, not JSON: exit 0 proceeds (stdout is
appended to the model's context), a non-zero exit blocks and hands **stderr** to
the model. There is no "allow" to emit, so the "decision only when blocking"
invariant holds by silence. Because *any* non-zero exit blocks, every error path
exits 0.

## Install

**macOS and Linux only for now — Windows is not supported yet.** The hook
commands and installer are bash; Kiro spawns Windows hook commands through
cmd.exe, so they never run there even though Windows binaries ship in `bin/`.
Windows support means: hook commands rendered per-OS by the installer to
invoke the binary directly (no shell), the binary loading the credentials
file itself, an `install.ps1`, a `[\\/]` path matcher, and validation against
Kiro's own open Windows hook issues (kirodotdev/Kiro#8264).

One command, once per machine — it covers every repository via Kiro's global
`~/.kiro/hooks/` path, downloads only the binary for the current platform
(checksum-verified), and prompts for the two credential values:

```bash
curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/kiro/scripts/install.sh | bash
```

To install into a single repository instead (the drop-in a team commits to
git so cloning developers get the hooks with no install step):

```bash
curl -fsSL .../kiro/scripts/install.sh | bash -s -- /path/to/repo
```

The script also runs from a local checkout of the marketplace tree, copying
instead of downloading. `CLOVER_MARKETPLACE_URL` overrides the download base
(the beta ring's raw URL, or a mirror). Layout after a machine-wide install:

```
~/.kiro/
  hooks/clover.json              # the three hooks above, absolute-path commands
  clover/
    scripts/run-hook.sh          # resolves the platform binary, loads env.sh, exec
    bin/clover-hook-<os>-<arch>
    env.sh                       # credentials — prompted, 0600, never committed
```

Credentials can also be pre-provisioned by dropping `env.sh` in place (MDM,
dotfiles) — the installer never overwrites an existing one.

The installer asks for four values and writes them to `env.sh`: client id,
client secret, and the two Clover hosts — **API `https://api.cloversec.io`** and
**auth `https://auth.cloversec.io`** — offered as defaults, so press enter unless
this is a non-production tenant. `CLOVER_SERVER_URL` / `CLOVER_AUTH_URL` preset
them for an unattended install, and the pair is echoed on the last line of the
install output. Wrong hosts are the one failure that looks like success: auth
fails, every hook fails open, and nothing reaches Clover.

Then open a repo in Kiro and **trust the workspace** (see below). Confirm with
the Output panel → Kiro agent channel:
`[KiroAgent] v2 hooks loaded 3 standalone hooks from .kiro/hooks/`.

## Workspace trust — required, or hooks stay silent

The tell in Kiro's own log is `hooks.v2.executionDisabledUntrustedWorkspace`.

Kiro turns **every** hook into a no-op in an untrusted folder, logging the
suppression only at debug level — valid files, no card, no error, nothing in
Clover. Every folder starts untrusted, so this is the most common reason a
working install looks dead. Pick one:

- **Trust a single folder** — open it in Kiro; when the trust banner appears,
  choose to trust it. Or command palette → **Workspaces: Manage Workspace
  Trust**. This is the safest option and the one to demo.
- **Trust a parent folder once** — in *Manage Workspace Trust*, add the folder
  that contains your repos (e.g. `~/Code`) to **Trusted Folders**. Everything
  under it is trusted automatically, so new repos need no per-folder step,
  while a repo cloned elsewhere still prompts.
- **Trust every folder (turn the gate off)** — add to Kiro's user
  `settings.json` (command palette → *Preferences: Open User Settings (JSON)*):

  ```json
  { "security.workspace.trust.enabled": false }
  ```

  Convenient, but it also lets hooks committed inside any repo you open run
  automatically — a deliberate reduction of Kiro's own protection. Prefer the
  parent-folder option unless you accept that trade-off. For a fleet, push this
  (or a trusted-folders list) through managed settings / MDM so the org owns
  the decision rather than each developer.

## When a new Kiro build changes its payload

Field naming has changed between builds and `PreTaskExec`'s shape is
undocumented, so the adapter accepts every spelling seen so far (`file_path`,
`filePath`, `path`, `spec_path`, `specPath`, `tool_input.specPath`) and falls
back to the most recently modified spec directory when an event names none. A
rename is therefore additive rather than breaking.

To see what a new build actually sends, run with `CLOVER_DEBUG=1` and read the
diagnostics log — the adapter records the event name and the spec it resolved.

## Known constraints

- **The IDE delivers an empty `prompt`**
  ([kirodotdev/Kiro#7500](https://github.com/kirodotdev/Kiro/issues/7500)), so
  prompt audit is a no-op there and posts nothing rather than a blank row; the
  CLI delivers the real text. Spec review is unaffected — the plan is read from
  disk.
- **Kiro does not close the hook's stdin.** A read to EOF hangs the turn until
  the hook times out, so Kiro's subcommands set `readsOneJSONValue` and stop at
  the end of the payload.
- **Every hook renders a chat card.** Kiro emits it at the engine level before
  the command runs; no setting or schema field suppresses it. All hooks are
  named `Clover Security`, the command and its output are never rendered, and
  the card collapses to a one-line summary when the turn ends.
- **Spec tasks can run concurrently**, so `PreTaskExec` may fire in parallel.
  The approved-plan-hash short-circuit in `runPlanReview` dedupes the common
  case.
- **`CodingAgentType` has no `Kiro` member** in Leaf yet, and the endpoints
  reject an unknown enum string, so activity is recorded as `Other`. Set
  `CLOVER_KIRO_CODING_AGENT=Kiro` (or change `kiroDefaultCodingAgent`) in the
  same release that adds the enum value.
- **Powers cannot carry hooks.** Kiro's power installer copies only `POWER.md`,
  `mcp.json` and `steering/`. A Clover *power* can ship steering and an MCP
  server; the hooks ship as this drop-in.

## The companion power

`clover-power/` is the Kiro *power* half of the surface: steering that teaches
the agent to honor Clover's review verdicts and `.clover-requirements.md`
files. Kiro installs powers straight from a Git URL — a subdirectory works via
a `/tree/<branch>/<path>` link — so once this tree is delivered to a
marketplace repo, install it with:

1. Command palette → **Powers: Configure** → **Import power from GitHub**.
2. Paste the marketplace URL for this directory, e.g. for the beta ring:
   `https://github.com/clover-security-public/clover-security-marketplace-beta/tree/main/kiro/clover-power`

The installer copies only `POWER.md` and `steering/` and registers the power as
`clover-power` (Kiro derives the name from the last path segment). The beta
marketplace repo is private, so the clone authenticates through your local git
credentials; the public marketplace URL needs none.

The power is optional and additive: the hooks enforce, the power only improves
how the agent responds to an enforcement. It ships no MCP server yet — Kiro's
remote-MCP auth against the Clover streaming endpoint is untested, and a
failing MCP entry would make the whole power look broken.

## Auto-update

Kiro has no plugin manager, so a `SessionStart` hook (`kiro-check-update`) keeps
the install current: when the channel's marketplace advertises a newer version,
the binary downloads its own replacement, verifies it against the tree's
`checksums.sha256`, and swaps it in with an atomic rename. Every failure path
fails open — the session always starts — and an install whose version cannot be
read is never replaced.

- **Public installs** update automatically from the public marketplace.
- **Beta installs** cannot self-download (the beta repo is private): they update
  by rerunning the installer, or by pointing at an internal mirror with
  `CLOVER_UPDATE_MANIFEST_URL` / `CLOVER_UPDATE_TREE_URL`.
- Only the **binary and version manifest** are refreshed. The hook config is
  path-rewritten at install time, so a new or changed trigger still needs a
  rerun of the installer.
- Cursor runs the same refresh at `sessionStart`, **on by default** on macOS and
  Linux (`CLOVER_CURSOR_SELF_UPDATE=0` opts a machine or fleet out). Windows is
  skipped before any download — a running executable cannot be renamed over
  there — so Windows Cursor installs update via Cursor's own marketplace flow.

## Debugging

`CLOVER_DEBUG=1` in `env.sh` for diagnostics, `CLOVER_KIRO_OBSERVE=1` to
downgrade the `PreTaskExec` gate to observe-only during a staged rollout, and
`CLOVER_HOOK_BIN` to point at a locally built binary.

The hook log is `<install dir>/.clover-hook.log`. Two auth failures come from a
wrong host in `env.sh` — both make every hook fail open, so the symptom is
silence in Clover rather than an error in Kiro:

| In the log | Cause | Fix |
|---|---|---|
| `auth returned 404 ... Failed to find vendor for host` | auth URL is not a Frontegg vendor host (e.g. `clover.frontegg.com`) | `CAS_CLOVER_PLUGIN_AUTH_URL=https://auth.cloversec.io` |
| auth or post failures, or no rows in Clover | API URL points at the webapp (`app.cloversec.io`), which redirects | `CAS_CLOVER_PLUGIN_SERVER_URL=https://api.cloversec.io` |

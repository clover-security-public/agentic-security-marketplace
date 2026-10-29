# Clover for GitHub Copilot

## Installation

```bash
copilot plugin marketplace add clover-security-public/agentic-security-marketplace
copilot plugin install clover@clover-security
```

Copilot has no prompt for plugin options, so credentials come from one of:

- **The environment Copilot starts in**: `CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID`
  and `CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET` (plus `_SERVER_URL` /
  `_AUTH_URL` for a non-default tenant). This is the only option on Windows, and
  the one fleet tooling should use.
- **`configure.sh`** on macOS and Linux, which writes `env.sh` (mode `0600`) into
  the plugin's data directory. For a marketplace install it finds that directory
  itself:

  ```bash
  bash ~/.copilot/installed-plugins/clover-security/clover/copilot/scripts/configure.sh
  ```

  The first session without credentials prints the exact command, data
  directory included.

Hooks run only in a trusted folder. Copilot skips them there silently, so
nothing is reviewed until the folder is trusted.

## How it works

Copilot reads `.plugin/plugin.json` and `.plugin/marketplace.json` ahead of the
`.claude-plugin/` pair, so a Copilot install runs `copilot/hooks/hooks.json` and
never the Claude or Devin hooks. Those use Claude's tool names and payloads,
which Copilot's native events do not match.

| Event | Matcher | Subcommand | Does |
| --- | --- | --- | --- |
| `sessionStart` | | `copilot-setup` | Tells the model to relay the setup command when credentials are missing |
| `sessionStart` | | `copilot-check-update` | Starts `copilot plugin update clover@<marketplace>` in the background when the channel has a newer version (at most every 6 hours) |
| `userPromptSubmitted` | | `copilot-log-prompt` | Records the prompt |
| `preToolUse` | `^exit_plan_mode$` | `copilot-review-plan` | Reviews the session's `plan.md`; denies with Clover's requirements until it passes |
| `preToolUse` | `^(create\|edit\|apply_patch)$` | `copilot-should-review-plan` | Reviews a Markdown plan written into the workspace |

`scripts/run-hook.sh` (POSIX) deploys the bundled binary into the data directory
after verifying it against `bin/checksums.sha256`, then runs it.
`scripts/clover-hook.cmd` (Windows) runs the bundled `.exe` in place. Both end
in exit 0 on every path, because a `preToolUse` hook that exits non-zero makes
Copilot deny the tool call.

## Not covered yet

- Windows and the VS Code Copilot agent: the hooks are written for them but not
  yet validated live.
- Copilot cloud agent: it ignores installed plugins and reads only
  `.github/hooks` from the default branch.

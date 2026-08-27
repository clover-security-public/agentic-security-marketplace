# What Clover runs

What each plugin in the `clover-security` marketplace installs, what its hooks
do, and what leaves your machine. `claude plugin details <plugin>` prints the
resolved inventory once a plugin is installed.

---

## `clover`

Reviews implementation plans for missing security requirements before code is
written.

| Event | Matcher | What we do | `async` |
| :-- | :-- | :-- | :-- |
| `SessionStart` | — | Set the plugin up on this machine, checksum-verified | `false` |
| `SessionStart` | — | Check for a newer plugin version and install it | `true` |
| `PreToolUse` | `ExitPlanMode` | Review the plan; return any missing security requirements | `false` |
| `PreToolUse` | `Edit\|Write\|MultiEdit` | For `.md` writes, check whether the file is a plan worth reviewing | `false` |
| `UserPromptSubmit` | — | Enrich the session's security context with the prompt | `true` |

**What leaves your machine:** the plan text, the content of `.md` files the
agent writes, your prompts, and the repository, branch, and developer identity
they belong to — sent to the Clover tenant you configure at install, and
nowhere else. GitHub is contacted only for update checks.

**Fail-open:** if anything goes wrong — no network, bad credentials, a crash —
the hook steps aside and your session carries on unaffected.

---

## `clover-for-security-teams` · `clover-for-developers`

| Component | `clover-for-security-teams` | `clover-for-developers` |
| :-- | :-- | :-- |
| `SessionStart` hook | Check for a newer version, at most once a day (`async`) | Same |
| Skill | `ask-clover` — security reviews, threats, required controls | `ask-clover-developer` — review the change you are working on, read back your reviews |
| MCP server | HTTP, at your Clover environment | HTTP, at your Clover environment |

The MCP endpoint defaults to `https://streaming.cloversec.io` and is
overridable at install for self-hosted tenants.

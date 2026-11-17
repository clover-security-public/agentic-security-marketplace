# Clover Security

**This power is guidance only.** It teaches the agent how to work with Clover's
security review of Kiro specs. It does not review, block or send anything
itself.

The review is done by Clover hooks named "Clover Security", which the developer
installs separately with Clover's installer (see Setting it up, macOS and Linux
only). Kiro's hook engine reads only `.kiro/hooks/` and `~/.kiro/hooks/`, never
a power's directory, so the power cannot install or run them. Once installed,
the hooks review each spec before implementation, return the security
requirements it is missing, and block the spec's tasks until they are covered.

## What the developer sees

- A blocked task start, whose error text lists the missing security requirements.
- A `.clover-requirements.md` file written beside the spec files.
- A steering file per spec (`.kiro/steering/clover-requirements-<spec>.md`), which
  Kiro includes in every later interaction.

## Working with a reviewed spec

1. If starting a task is blocked with security requirements, fold each one into
   `requirements.md` and `design.md`, then start the task again — the review
   re-evaluates the updated spec. Do not retry unchanged and do not work around
   the block.
2. If a `.clover-requirements.md` file exists in the spec directory, read it
   before implementing and satisfy every requirement in the code you write.
3. Never delete, truncate or edit `.clover-requirements.md` to make a review
   pass. Clover clears it once the requirements are genuinely covered; a cosmetic
   edit comes back denied with the same requirements standing.
4. When you have satisfied Clover requirements in code, say which ones and how,
   so the developer can verify each.

## Setting it up

When the developer asks to set Clover up, give them this command to run **in
their own terminal**, once per machine — it covers every repository:

```bash
curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/kiro/scripts/install.sh | bash
```

Do not run it for them: it prompts for the Clover client id and secret (from
Clover Settings → API Tokens), and only the developer can answer. If it prints
`already installed`, Clover is already active — that is success.

Then two things make a correct install look dead:

- **Workspace trust.** Kiro turns every hook into a no-op in an untrusted
  folder. Trust the workspace.
- **Credentials.** Without them every hook fails open and nothing reaches
  Clover. They live in `~/.kiro/clover/env.sh`.

macOS and Linux only; the hooks do not run on Windows. The `clover-setup` skill
covers what the installer writes, what data the hooks send to Clover, automatic
updates, and how to remove it.

## Skills and tools

- `clover-spec-review` — working with a spec Clover has reviewed.
- `clover-setup` — installing, verifying and removing the Clover hooks.

This power ships no MCP server. The review runs through the hooks; the
`.clover-requirements.md` files and the blocked-task error text are the whole
interface.

## License and support

AGPL-3.0-only (see `LICENSE`). Support: <https://clover.security/support/>.
Privacy policy: <https://clover.security/privacy-policy/>.

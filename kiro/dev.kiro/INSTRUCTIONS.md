# Clover Security

Clover is a security review layer for agentic coding. It reviews the spec you are
about to implement, returns the security requirements it is missing, and blocks
the task until they are covered.

The review runs as hooks named "Clover Security", not as this power: Kiro's hook
engine reads only `.kiro/hooks/`, never a power's directory. Until the hooks are
installed (see Setting it up), this power is guidance only and nothing is being
reviewed.

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

macOS and Linux only; the hooks do not run on Windows.

## Tools

This power ships no MCP server. The review runs through the hooks; the
`.clover-requirements.md` files and the blocked-task error text are the whole
interface.

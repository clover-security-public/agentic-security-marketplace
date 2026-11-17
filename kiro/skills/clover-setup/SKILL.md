---
name: clover-setup
description: Use when the developer asks to set up, install, verify, troubleshoot or remove Clover Security in Kiro, or asks why Clover is not reviewing their specs. Explains that this power is guidance only, how the separate Clover hook installer works, what it changes on the machine, and what data the hooks send to Clover.
---

# Setting up Clover Security in Kiro

**This power does not review or block anything on its own.** Kiro's hook engine
reads hooks only from `.kiro/hooks/` (in a repository) and `~/.kiro/hooks/`
(machine-wide), never from a power. Clover's spec review and task gate run as
hooks that the developer installs with Clover's installer. Until then, nothing is
reviewed and no task is blocked.

Supported on **macOS and Linux only**. The hooks and installer are bash, and Kiro
runs Windows hook commands through `cmd.exe`, so they do not run on Windows.

## Install

Give the developer this command to run **in their own terminal**. Do not run it
for them: it prompts for the Clover client id and secret (Clover Settings → API
Tokens), and only the developer should type those.

Machine-wide (covers every repository opened in Kiro on this machine):

```bash
curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/kiro/scripts/install.sh | bash
```

One repository only (the drop-in a team commits so cloning developers get it):

```bash
curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/kiro/scripts/install.sh | bash -s -- /path/to/repo
```

Suggest the developer read the script before piping it to bash. Use one scope
per machine; the installer refuses the second and prints `already installed`,
which is success.

## What the installer changes

Machine-wide it writes under `~/.kiro/`; for one repository, under
`<repo>/.kiro/` and two lines in that repository's `.gitignore`:

- `hooks/clover.json` — four hooks named "Clover Security": `SessionStart`
  (update check), `UserPromptSubmit` (prompt audit), `PostFileSave` on
  `.kiro/specs/**/*.md` (spec review), `PreTaskExec` (the gate that blocks a
  task while security requirements stand).
- `clover/scripts/run-hook.sh` and `clover/bin/clover-hook-<os>-<arch>` — the
  launcher and a compiled binary for this platform only, verified against the
  published `checksums.sha256` before it is installed. The binary's source is
  public: <https://github.com/clover-security-public/clover-hook-source>.
- `clover/env.sh` — the credentials and Clover hosts, file mode 0600, never
  committed.

The `SessionStart` hook updates the binary automatically from the public
marketplace, with the same checksum verification. To turn that off, set
`"enabled": false` on the `SessionStart` entry in `hooks/clover.json`, and
update by re-running the installer instead.

## What leaves the machine

The installer shows this list and asks the developer to confirm before it writes
anything. The hooks send the developer's prompts to Kiro (including those Kiro
keeps in its local session store), each spec under review, and its context —
repository name and remote URL, branch, git `user.email` and `user.name`, the
Clover plugin version, the operating system and Kiro's session id — to the
Clover tenant configured in `env.sh`, along with hook failure reports. They read
no other application's account settings. The client id and secret are used
only to authenticate to that tenant's auth host. The update check downloads
from the public Clover marketplace repository on GitHub. Privacy policy:
<https://clover.security/privacy-policy/>.

## Verify

1. Trust the workspace (Kiro silently disables every hook in an untrusted
   folder).
2. Send any prompt: one "Clover Security" card appears in the chat.
3. Ask Kiro for a spec with obvious security surface (for example a login
   endpoint). A few seconds after the spec is finished, a
   `.clover-requirements.md` file appears beside it.
4. Starting a task is blocked until those requirements are folded into the spec.

If nothing reaches Clover, check the credentials and hosts in
`~/.kiro/clover/env.sh` (API `https://api.cloversec.io`, auth
`https://auth.cloversec.io`) and the log at `~/.kiro/clover/.clover-hook.log`.

## Remove

Machine-wide: delete `~/.kiro/hooks/clover.json` and `~/.kiro/clover/`. One
repository: delete `<repo>/.kiro/hooks/clover.json`, `<repo>/.kiro/clover/` and
the Clover lines in its `.gitignore`; its runtime state is under
`~/.kiro/clover-state/`. Then uninstall this power from Kiro's Powers panel.

Support: <https://clover.security/support/>.

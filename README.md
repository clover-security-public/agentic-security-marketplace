<div align="center">

# 🍀 Clover for Coding Agents

### Ship secure code at agent speed.

Clover silently reviews every plan your AI coding agent makes, surfaces the security requirements it missed, and folds them into the work **before a single line of code is written** — no questions, no detours, no slowdown.

[**📖 Full Setup Guide →**](https://docs.cloversec.io/product-guides/securing-agentic-development/connecting-clover-to-coding-agents)

</div>

---

## Quick start

> **Prerequisites:** A Clover account. Grab your API credentials from **Clover Settings → API Tokens**. You'll need: `server_url`, `auth_url`, `client_id`, and `client_secret`.

### Claude Code

1. **Add the Clover marketplace:**
   ```
   /plugin marketplace add clover-security-public/agentic-security-marketplace
   ```
2. **Install the plugin:**
   ```
   /plugin install clover
   ```
3. **Enter your credentials** when prompted (`server_url`, `auth_url`, `client_id`, `client_secret`).
4. **That's it.** From your next plan onward, Clover reviews automatically — no further action needed.

### Cursor

1. Install the **Clover** plugin from the Cursor plugin marketplace.
2. Provide your Clover API credentials.
3. Start planning — Clover reviews every plan in the background.

### Windows

The plugin ships native Windows executables for x64 and ARM64. Claude Code's
native Windows setup already requires Git for Windows; Cursor users should
install [Git for Windows](https://git-scm.com/download/win) and make sure
`bash.exe` is available on `PATH`.

## What Clover installs

Every hook Clover registers is documented before you install it. After
installing, `claude plugin details clover` prints the resolved component
inventory and its context cost.

[**🔎 What Clover runs, and what leaves your machine →**](USAGE.md)

## Turning off automatic updates

Clover keeps itself current: at the start of each session it checks for a newer
version and installs it. Where an agent supports it, you can turn this off and
roll out updates yourself.

| Coding agent | Turn off automatic updates |
| --- | --- |
| Cursor | Set `CLOVER_CURSOR_SELF_UPDATE=0` |
| Codex | Set `CLOVER_CODEX_SELF_UPDATE=0`, or add `export CLOVER_CODEX_SELF_UPDATE=0` to Clover's Codex `env.sh`. MDM-managed installs never update themselves. |
| Claude Code | Not supported |
| GitHub Copilot | Not supported |
| Devin | Not supported |
| Kiro | Not supported |

Set the variable in the environment the agent starts from; for a fleet, set it
through your MDM. `0`, `false`, `off` and `no` all turn updates off. With
updates off, Clover makes no network request to check for a new version.

---

👉 **For detailed, screenshot-by-screenshot instructions, org-wide rollout, and troubleshooting, see the [Connecting Clover to Coding Agents guide](https://docs.cloversec.io/product-guides/securing-agentic-development/connecting-clover-to-coding-agents).**

---

<div align="center">
<sub>Built by Clover Security · Protect your coding-agent experience.</sub>
</div>

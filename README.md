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

---

👉 **For detailed, screenshot-by-screenshot instructions, org-wide rollout, and troubleshooting, see the [Connecting Clover to Coding Agents guide](https://docs.cloversec.io/product-guides/securing-agentic-development/connecting-clover-to-coding-agents).**

---

<div align="center">
<sub>Built by Clover Security · Protect your coding-agent experience.</sub>
</div>

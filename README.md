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

### Self-hosted Clover environments

`clover-for-developers` and `clover-for-security-teams` connect to Clover Cloud by default. If Clover runs in your own environment, point them at your host with the plugin's `streaming_url` option. Nothing to change on Clover Cloud.

| How | When to use it |
|-----|----------------|
| `/plugin configure clover-for-developers@clover-security` | A single developer, after installing |
| `claude plugin install clover-for-developers@clover-security --config streaming_url=https://streaming.acme.example.com` | Scripted installs and onboarding |
| `pluginConfigs` in managed settings (below) | Whole organization, no developer action |

For an org-wide rollout, add this to your managed settings file (`/Library/Application Support/ClaudeCode/managed-settings.json` on macOS, `/etc/claude-code/managed-settings.json` on Linux):

```json
{
  "pluginConfigs": {
    "clover-for-developers@clover-security": {
      "options": { "streaming_url": "https://streaming.acme.example.com" }
    },
    "clover-for-security-teams@clover-security": {
      "options": { "streaming_url": "https://streaming.acme.example.com" }
    }
  }
}
```

> `pluginConfigs` is read from user settings, `--settings`, and managed settings only. Entries in a project's `.claude/settings.json` are ignored by design.

👉 **For detailed, screenshot-by-screenshot instructions, org-wide rollout, and troubleshooting, see the [Connecting Clover to Coding Agents guide](https://docs.cloversec.io/product-guides/securing-agentic-development/connecting-clover-to-coding-agents).**

---

<div align="center">
<sub>Built by Clover Security · Protect your coding-agent experience.</sub>
</div>

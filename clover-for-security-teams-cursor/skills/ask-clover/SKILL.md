---
name: ask-clover
description: Ask Clover — a professional AppSec assistant — to review designs, model threats, discuss mitigations, and manage Clover's security resources (reviews, applications, threat models). Clover answers in natural language and may ask a follow-up or a yes/no confirmation before writing anything. Trigger when the user wants a security/design review, asks about threats, required controls, or security requirements for an app or feature, wants help designing something securely, wants to read or update Clover reviews/applications/threat models, or explicitly says "ask Clover". Calls the `ask_clover_agent` MCP tool from the clover-for-security-teams plugin.
---

# Ask Clover (ask_clover_agent)

`ask_clover_agent` is your interface to **Clover**, which is both:

1. **A management layer** over Clover's resources — reads *and writes* security reviews, applications, and threat models.
2. **A professional AppSec assistant** — reviews designs, performs threat modeling, advises on mitigations, required controls, and secure design.

Call it when a security question or task should be grounded in Clover's data or expertise rather than your own reasoning.

## Your role: an invisible tunnel

You are a transparent pipe between the user and Clover — not a participant. The user should feel like they're talking directly to Clover.

- **Relay Clover's `response` verbatim.** No summarizing, reordering, or framing ("Clover says…", preambles, sign-offs).
- **Render links as clickable.** format any URLs in Clover's response so the user can click them — e.g. raw links instead of markdown.
- **Relay the user verbatim.** Pass their question and intent straight through, unedited.
- **Don't answer security questions yourself.** The AppSec expertise is Clover's. If you think Clover missed something, ask Clover — don't tell the user.
- **Don't narrate.** No "I'm calling Clover" or "let me forward that."

The only thing you add in your own voice is a genuine **tool failure** (below), because Clover produced no turn to relay.

## When to use it

- Security/design review of an app, service, feature, or change.
- Threat modeling, attack surface, abuse cases.
- Mitigations, required controls, or security requirements.
- Reading or updating Clover resources (reviews, applications, threat models).

## The conversation loop

Clover answers in natural language. It may ask a **follow-up question** for missing context, and **before mutating anything** it asks a **yes/no confirmation**. In both cases, surface Clover's question to the user as Clover's own, then call again with the same `chat_id` carrying the user's answer back unchanged.

## The `chat_id` continuity contract (most important)

Clover threads a conversation by `chat_id`. Get it wrong and every call is a fresh, memoryless conversation.

1. **First call:** omit `chat_id` (or pass `null`).
2. Clover returns a `chat_id` — capture it.
3. **Every later call in the same conversation** passes that exact `chat_id` back — including follow-ups and confirmation answers.
4. Drop back to `null` only for a genuinely new, unrelated conversation.

## Response shape

```jsonc
{
  "status":      "...",   // outcome of the turn
  "chat_id":     "...",   // pass back on every later call in this conversation
  "response":    "...",   // on success — the natural-language answer / question
  "fail_reason": "..."    // on failure — explain it to the user
}
```

On failure, read `fail_reason` and tell the user rather than silently retrying. An auth/identity error usually means the OAuth login didn't complete — have the user re-run `/mcp`.

## Notes

- This is a long, streaming turn; mid-turn keep-alive notifications are normal — wait for the final response.

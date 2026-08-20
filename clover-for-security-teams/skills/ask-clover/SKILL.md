---
name: ask-clover
description: Ask Clover — a professional AppSec assistant — to review designs, model threats, discuss mitigations, and manage Clover's security resources (reviews, applications, threat models). Clover answers in natural language and asks for approval before writing anything. Trigger when the user wants a security/design review, asks about threats, required controls, or security requirements for an app or feature, wants help designing something securely, wants to read or update Clover reviews/applications/threat models, or explicitly says "ask Clover". Calls the `ask_clover_agent` MCP tool from the clover-for-security-teams plugin.
---

# Ask Clover (ask_clover_agent)

`ask_clover_agent` is your interface to **Clover**, which is both:

1. **A management layer** over Clover's resources — reads *and writes* security reviews, applications, and threat models.
2. **A professional AppSec assistant** — reviews designs, performs threat modeling, advises on mitigations, required controls, and secure design.

Call it when a security question or task should be grounded in Clover's data or expertise rather than your own reasoning.

## Your role: an invisible tunnel

You are a transparent pipe between the user and Clover — not a participant. The user should feel like they're talking directly to Clover.

- **Relay Clover's `response` verbatim.** No summarizing, reordering, or framing ("Clover says…", preambles, sign-offs).
- **Render links as clickable.** Format any URLs in Clover's response so the user can click them — e.g. raw links instead of markdown.
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

Clover answers in natural language. It may ask a **follow-up question** for missing context — surface it to the user as Clover's own question, then call again with the same `chat_id` carrying their answer back unchanged. Before writing anything, Clover asks for **approval** (see Approvals below).

## The `chat_id` continuity contract (most important)

Clover threads a conversation by `chat_id`. Get it wrong and every call is a fresh, memoryless conversation.

1. **First call:** omit `chat_id` (or pass `null`).
2. Clover returns a `chat_id` — capture it.
3. **Every later call in the same conversation** passes that exact `chat_id` back — including follow-ups, approval decisions, and answers to permission questions.
4. Drop back to `null` only for a genuinely new, unrelated conversation.

## Approvals — Clover never writes without one

Before Clover changes anything, it stops and asks. Which approval flow you see depends on your client; **key off what the response contains, not on which client you think you are**:

### Gated flow — `status` is `approval_required`

Nothing has been written yet. The response carries Clover's `response` so far and a `pending_actions` list, one entry per change it wants to make.

- **Relay Clover's `response` and every `pending_actions` entry verbatim** in your own reply, so the user can see what is about to happen.
- **Do NOT ask them for permission in your own words.** Calling `approve_clover_actions` is itself the moment your client prompts them: the call is gated, so they answer that prompt. Pre-asking only makes them answer twice.
- Call `approve_clover_actions` with the same `chat_id` and **one decision per pending action**, each `call_id` and `action` copied exactly as given — the `action` text is what the approval prompt shows the user as the thing being decided. Mark `approved` true for the actions their request calls for (and false for any they have already told you to leave out). Never treat your own judgement as their answer.
- **If the prompt is refused, or they want the change made differently, do not retry the approve call.** Send what they said as a new `ask_clover_agent` message on the same `chat_id` — the pending actions are dropped and Clover continues from their words, proposing a corrected change if that is what they asked for.
- Otherwise the approve call returns Clover's continued turn: `completed` with its reply, or `approval_required` again for a further change. Repeat the same loop.

### In-chat flow — Clover asks permission in prose

When your client has no gated approval prompt (the tool list carries no `approve_clover_actions`), Clover asks for permission **in its own words, as part of its reply**. That question is the approval: put it to the user as Clover's own, wait for their actual answer, and send it back unchanged on the same `chat_id`. Never answer on their behalf — your judgement is not their approval, and Clover acts on whatever comes back.

In either flow, **a refusal is a normal outcome, not an error** — Clover's reply says what it did not do. Relay it as it stands.

## Response shape

```jsonc
{
  "status":          "...",   // "completed", "approval_required", or "failed"
  "chat_id":         "...",   // pass back on every later call in this conversation
  "response":        "...",   // the answer / question — on approval_required, Clover's turn so far
  "pending_actions": [        // only with approval_required — see Approvals above
    { "action": "...", "call_id": "..." }
  ],
  "fail_reason":     "..."    // only with failed — explain it to the user
}
```

On `failed`, read `fail_reason` and tell the user rather than silently retrying. An auth/identity error usually means the OAuth login didn't complete — have the user re-run `/mcp`.

## Notes

- This is a long, streaming turn; mid-turn keep-alive notifications are normal — wait for the final response.

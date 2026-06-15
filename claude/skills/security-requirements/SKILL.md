---
name: security-requirements
description: Silently threat-model the work in flight, fold mitigations into the implementation plan, and keep going. Dispatches on argument; currently supports `threat-questions` (STRIDE-style threat model). Trigger when the user runs `/security-requirements [mode]`, or proactively when a plan or feature touches authentication, authorization, user input, sensitive data (PII, secrets, tokens), network requests, file access, or third-party integrations. Also trigger on phrases like "threat model this", "security requirements", or "what could go wrong security-wise".
hooks:
  Stop:
    - hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-hook.sh log-skill security-requirements"
---

# Security Requirements

Surface security thinking *without interrupting the developer*. Claude does the threat model itself, records the result inline, and continues coding.

**Hard rule:** never ask the user threat-modeling questions. If something is genuinely unknowable from context, pick the safer default and note the assumption in the output. The developer's time is more valuable than perfect threat coverage.

## Dispatch

Read the argument that follows `/security-requirements`:

| Argument | Mode |
| --- | --- |
| `threat-questions` (default if omitted) | STRIDE-style threat model — see [Mode: threat-questions](#mode-threat-questions) |

If the argument is unrecognized, list the supported modes once and default to `threat-questions`. Do not invent new modes.

When triggered proactively (no slash command — Claude noticed a sensitive area in the plan), use `threat-questions`.

---

## Mode: threat-questions

### What it does

1. **Read the plan / current request silently.** Identify the entry point and trust boundary from what's already on screen — the user's prompt, the plan, the diff, the file being edited.
2. **Run STRIDE internally** against that boundary. Skip categories that don't apply. Do not enumerate categories that don't fire.
3. **Pick concrete mitigations.** For each threat that applies, decide a specific code/config change. If a real mitigation can't be picked without more info, choose the safer default and label it as an assumption.
4. **Emit a short `## Threats considered` block** (format below). This is the only user-visible artifact.
5. **Fold mitigations into the implementation plan / TODO list / next steps**, then keep going. Do not stop and wait.

### What it must not do

- Do **not** ask the user numbered questions and wait.
- Do **not** dump the full STRIDE checklist if only two categories apply.
- Do **not** repeat the threat model on follow-up turns for the same task — once is enough.
- Do **not** block implementation. The threat block is a side note, not a gate.

### Output format

Emit exactly this block, then continue with implementation:

```
## Threats considered

- **<threat>** → <concrete mitigation tied to a file, config, or step>
- **<threat>** → <mitigation> _(assumption: <what was inferred>)_
```

Keep it to 2–5 bullets. If a threat is real but explicitly out of scope, mark it `_(out of scope — owner: <team or follow-up ticket>)_` instead of inventing a fix.

### STRIDE reference (internal — for Claude's reasoning, not for the user)

- **S — Spoofing:** identity at the entry point. Forgery, replay, missing auth, trusted-header spoofing.
- **T — Tampering:** input validation/bounds; integrity in transit and at rest.
- **R — Repudiation:** audit trail for sensitive actions; tamper-evidence.
- **I — Information disclosure:** PII/secrets/tokens flowing through code, logs, errors, responses.
- **D — Denial of service:** input size/depth/rate; expensive operations without timeouts or limits.
- **E — Elevation of privilege:** authz checks; IDOR; missing checks on sub-paths; assumed-trusted callers.

### Example

User: "Add an endpoint that lets users export their data as a CSV."

Claude (after writing the implementation plan, before the first code change):

> ## Threats considered
>
> - **Authorization (E)** → scope the export query to `request.user.id`; add a unit test for cross-tenant access returning 404.
> - **Information disclosure (I)** → strip `internal_id`, `deleted_at`, and any joined columns from other tenants in the serializer.
> - **DoS (D)** → cap rows at 100k per export; stream the response instead of buffering.
> - **CSV injection (T)** → prefix any cell starting with `=`, `+`, `-`, `@` with a single quote when writing rows.
> - **Audit (R)** _(assumption: compliance is in scope based on PII handling)_ → log `user_id`, row count, and timestamp to the existing audit pipeline.

…then proceeds to implement, with each bullet appearing as a step in the plan.

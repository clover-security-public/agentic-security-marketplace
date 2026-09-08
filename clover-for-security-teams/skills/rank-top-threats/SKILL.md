---
name: rank-top-threats
description: >-
  Lists the highest-risk open threats for one security review, one application, or the whole
  organization, ranked by Clover's threat level, with the consequence of each. Use when asking what to
  fix first.
disable-model-invocation: true
---
# Rank Top Threats

Answers "what should we fix first?"

Clover holds the data and does the analysis. This skill asks well, reads the answer correctly, and lays it out. It never derives, judges, or re-analyses on Clover's behalf.

## 1. Scope the request

**Ask the user which scope they mean** before searching: one security review, one application, or the whole organization. The three produce different lists, and the org-wide one is far longer. A review link or name in the conversation usually means that review; an application name means the application. When the user named a review or an application, have Clover resolve it; when the name matches several, list the candidates and let the user pick.

## 2. Ask Clover

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call.

1. **The ranked list**: ask for the open threats at the top threat levels in that scope, ordered by threat level, each with its status and what it would cost if realized, plus its owning review when the scope is an application and its application as well when the scope is the organization.
2. **The totals**: ask for the count of open threats broken down by threat level, and by application when the scope is org-wide. One request, not one per application.
3. **Both threat sets**: ask for review-derived threats and threat-model threats separately. A single review carries only review-derived threats; the threat model belongs to the application, so for a review scope say that the model's threats are out of scope rather than reporting them as absent.

## 3. Read the answer

- **Threat level is the ranking.** It is Clover's combination of impact and likelihood; impact alone is a different field. Quote the one Clover gave and never restate one as the other.
- **Keep the two sets apart.** An application with no threat model has none of that kind. That is an absence, not an empty result.
- **Use Clover's totals**, not a count of the rows returned; lists come back a page at a time.
- **Zero means zero.** Report it rather than re-asking with looser filters.

## 4. Present it

A table: Threat · Level · Application / review (drop the columns the scope makes constant) · Status · What it costs, most severe first, top 10 unless more was asked for. Above it, one line naming the scope and the true total. Below it, the ones Clover flagged as most pressing.

Offer the Clover-themed page via `publish-clover-artifact` when the user wants to share it.

---
name: summarize-review
description: >-
  Reads a security review back as a short summary for people who do not open Clover: the outcome, the
  threats that matter, outstanding requirements, and open questions. Use when sending a review's
  results to a team, a ticket, or Slack.
disable-model-invocation: true
---
# Summarize Review

One review, readable in a minute by a product manager or a developer.

Clover holds the data and does the analysis. This skill asks well, reads the answer correctly, and lays it out. It never derives, judges, or re-analyses on Clover's behalf.

## 1. Scope the request

Resolve to one review, and note who the summary is for: the audience decides how much detail is worth carrying.

## 2. Ask Clover

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call.

1. **The review**: ask for its application, what it covers, its status, and its workflow position.
2. **The findings**: ask for its threats with levels and statuses, its requirements with priorities and statuses, and its open questions, with the totals for each.
3. **What matters**: ask Clover which findings it considers the ones worth naming, rather than picking from the list here.

## 3. Read the answer

- **Say whether the analysis has finished.** A review still analysing has provisional findings; label them.
- **Rank threats by threat level and requirements by priority**, naming which rating is quoted.
- **Use Clover's totals**, never a count of the rows returned.
- **Open questions are part of the outcome**: they are what the review is waiting on.

## 4. Present it

```markdown
# <review name> · <application>
**Where it stands:** <status, and whether analysis is complete>
## Threats
| Threat | Level | Status | What it costs |
## Requirements
<satisfied vs outstanding, high-priority ones named>
## Open questions
## What's next
```

Drop any section Clover gave no data for. Offer a short cut for Slack or a ticket, and the shareable page via `publish-clover-artifact`.

---
name: brief-application
description: >-
  A one-page security briefing for a single application, written for its accountable owner: what it
  is, its open threats, control status, review history, threat-model coverage, and accepted risks. Use
  when asking where one application stands.
disable-model-invocation: true
---
# Brief Application

The current standing of one application: where it is now, not what moved this month.

Clover holds the data and does the analysis. This skill asks well, reads the answer correctly, and lays it out. It never derives, judges, or re-analyses on Clover's behalf.

## 1. Scope the request

Confirm Clover resolves the name to a single application; when it matches several, list the candidates and let the user pick: a briefing on the wrong application is worse than none. Note its business unit; the owner reads their application in that context.

**When no application was named, narrow before searching.** Ask for the business units first, then which applications in the chosen unit have the most security reviews, and pick from that. **Never ask for a tenant-wide list of applications that have a threat model**: there is no index of it, so the request becomes a long sweep that returns empty.

## 2. Ask Clover

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call.

1. **Identity and exposure**: what it is, its business unit, risk profile, attached frameworks, whether it is internet-facing, and the data sensitivity on record.
2. **Threat-model coverage**: its target of evaluation, actors, trust zones, and assumptions. Do not ask when the model was built or last recalculated; Clover holds no such date.
3. **Open threats, both sets**: review-derived and threat-model threats, each with its status breakdown and highest-severity open items.
4. **Required controls**: which frameworks and controls apply, and satisfied versus outstanding requirements by status and priority, as counts by framework.
5. **Reviews**: completed and in flight, with outcomes.
6. **Accepted risks**: what was accepted and by whom. Acceptance applies only to review-derived threats, and Clover does not report expiry. Do not ask whether one is stale.
7. **Workflow state**: where its reviews sit and how long the current step has been active.
8. **What keeps recurring**: ask for the application's threat baseline, the risk categories that group its review threats with their scores, and which categories or requirements appear across several separate reviews. One finding is a ticket; the same finding across six reviews is a platform problem, and the owner should see it named.

## 3. Read the answer

- **Standing, not movement**: a long-open threat belongs here precisely because it is still open.
- **Keep the two threat sets distinct**; blending them produces a number matching nothing in Clover.
- **An absent record is written as absent**: "not on record", never inferred from the application's name or stack. When the absence is the story, lead with it.
- **Severity is not impact**: give Clover's rating and its consequence separately.
- **Tracking tickets: attachment only**, never their live state.
- **Reconcile before writing.** If two answers disagree on a total, ask Clover which is correct; if it cannot resolve it, report both and say they disagree.
- **Recurrence is Clover's grouping**, never a second clustering built here, and it means across reviews, not within one: a single review raising five related threats is one design, not a pattern. No pattern is a good result; report it rather than assembling one from findings that share a word.
- **Approve reads, never writes**, and say which reads you approved.

## 4. Present it

Standing line · the application · threat model (or the plain statement that none exists) · open threats as two labelled tables · controls · reviews · accepted risks · what keeps recurring (only when Clover reports a pattern spanning several reviews) · what is on the owner's plate. Drop empty sections rather than filling them.

A briefing carries a live application's weaknesses, so do not publish by default. Offer the page via `publish-clover-artifact` and let the user decide.

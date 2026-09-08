---
name: start-security-review
description: >-
  Creates a Clover security review from a design doc, ticket, or pull request. Analysis takes minutes,
  so the user picks how to wait: sync (keep polling Clover until the findings are ready) or async
  (create the review, end the turn, and read the findings back on a later visit). Use when a link needs
  reviewing, assessing, or auditing.
disable-model-invocation: true
---
# Start Security Review

Creation is instant; the analysis is not. This sets the right expectation, lets the user choose how to wait, and comes back for the results.

Clover holds the data and does the analysis. This skill asks well, reads the answer correctly, and lays it out. It never derives, judges, or re-analyses on Clover's behalf.

## 1. Scope the request

A shared link is not a request to review it. "Review this", "assess", "audit", or a yes to your offer is. Otherwise name the option and wait.

One change, one review. Several links describing the same change go into a single creation, the first as the seed and the rest as related context; independent changes each need their own. When it is unclear whether it is one change or several, ask.

## 2. Choose the mode

Before creating anything, offer the two ways to wait and let the user pick. Explain both in a sentence each:

- **Sync**: you create the review and keep polling Clover until the analysis has finished, then read the findings back in this same turn. The user waits several minutes but gets the results without coming back.
- **Async**: you create the review and stop. The analysis runs on Clover's side, and the user returns in a later turn to read the findings.

Skip the question when the user has already said which they want: "wait for it", "poll until it is done", or "keep me posted here" is sync; "just kick it off", "start it and I'll check later", or "don't wait" is async. Never pick a mode for them otherwise.

## 3. Ask Clover

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call.

1. **Existing coverage**: ask whether a review already exists for this change before creating anything.
2. **The creation**: ask Clover to create the review from the URLs, naming the application if the user gave one.
3. **Checking on the analysis**: ask whether the analysis has finished, and then for the findings. In sync mode this happens in the same turn, on a loop; in async mode only when the user returns.

## 4. Read the answer

- **An empty result during analysis means "not ready", never "clean".** Never report findings, no findings, or a summary while analysis is running.
- **An existing review returned instead of a new one is a normal outcome**: report it as coverage that already exists.
- **A Clover web-app link is never a source**: it identifies a review that already exists.

## 5. Present it

After creating, give the review's name and link and say the analysis runs for several minutes. What happens next depends on the mode.

**Async**: **end the turn**. Nothing moves time forward except the user's next message: no polling, no re-checking, no background waiting. Ending the turn with analysis unfinished is the correct outcome: the review is safe and a later turn picks it up. When the user returns and analysis is done, hand off to `summarize-review`.

**Sync**: poll on the same `chat_id`. Ask Clover whether the analysis has finished; if not, wait about a minute before asking again, using whatever wait or sleep facility the environment offers, and say once that you are waiting rather than narrating every check. Keep going until Clover reports the analysis done, then ask for the findings and hand off to `summarize-review`. If the analysis is still running after roughly fifteen minutes, or the user interrupts, fall back to the async ending: give the link again, say the review is still analysing, and end the turn.

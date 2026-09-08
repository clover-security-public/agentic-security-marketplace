---
name: triage-review
description: >-
  Triages a security review's findings with the security team: shows what is open on the review, both
  the findings waiting on a security decision (dismissal or risk acceptance proposed by a developer) and
  the rest of the open plate, asks what new information could move them, and records the outcomes as
  threat and requirement statuses, priorities, impact and likelihood, each with the reasoning, after
  showing the intended changes for confirmation. Use when working a review's open findings or recording
  a triage session's verdicts.
disable-model-invocation: true
---
# Triage Review

One loop: see what is open on the review, bring what you know, decide, and record it, with a visible diff before anything is written.

Clover holds the data and does the analysis. This skill asks well, reads the answer correctly, and lays it out. It never derives, judges, or re-analyses on Clover's behalf.

## 1. Scope the request

Scope to one review, one application, or the user's own reviews. Then settle where the user is starting:

- **Looking at the plate**: they have not brought decisions yet. Run steps 1 and 2 below, present the plate, then ask the question in step 3.
- **Recording**: they bring decisions, or new information that bears on specific findings. The decisions are the user's. Collect them, and match each to exactly one finding before writing anything.

The plate has two parts that need separating. **Waiting on security**: a developer proposed a disposition and nothing moves until someone approves or rejects it; two proposals share that state, **dismissal proposed** (the developer says it does not apply) and **risk acceptance proposed** (it applies, and they ask to accept it anyway). **Open otherwise**: everything else still open, requiring attention, pending developer, or unanswered, where the security team can move things by adding what it knows: a control that already exists, a design fact that lowers likelihood or impact, evidence that a requirement is met.

## 2. Ask Clover

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call.

1. **Waiting on security**: ask for the findings pending security approval in that scope, threats and requirements alike, with their review and application; which disposition each developer asked for and the reasoning they gave; how long each has been waiting; and what approving or rejecting would do to the finding.
2. **Open otherwise**: ask for the remaining open findings in that scope with their kind, rating (threat level with its impact and likelihood for threats, priority for requirements), status, what each asks for, and what would satisfy or reduce it.
3. **Ask the user what they know.** After presenting the plate, ask one question: does the user have information that could drive any of these forward? Existing controls, compensating measures, architecture facts, evidence, or a decision. Check the conversation first: the answer is often already there from an earlier skill or a pasted document. Name the findings that information seems to touch, and let the user confirm.
4. **The judgement, where one is needed**: when the user's information needs weighing against what a finding asks, ask Clover whether it satisfies the finding, or how it changes the threat's impact or likelihood, rather than deciding here.
5. **The writes**: after the user confirms the diff, ask Clover to apply each change, passing the user's own words as the reasoning.

Clover asks for approval on each write. Approve only what the user just confirmed.

## 3. Read the answer

- **A finding waiting on security still reads as open.** Its underlying status stays "requires attention" until someone acts, so a raw open count includes items parked on the security team. Say which of the open items are in that part of the plate.
- **Present the proposal; do not rule on it.** The approve-or-reject call is the user's. Name the person and the date where the record has them. An empty waiting list is a good answer.
- **New information changes a record only through Clover's judgement.** The user supplies the fact; Clover says what it does to the finding; the user confirms; then it is written. Never mark a finding mitigated because the user's fact sounds sufficient here.
- **Threat level cannot be set.** It moves only when impact or likelihood changes; if the user says "make this a high", ask which they mean.
- **Report what actually landed.** A declined or failed write stays out of the applied list.
- **Risk acceptance is a decision**: the acceptor and the reasoning are the record an auditor reads later.

## 4. Present it

**The plate**, in two tables. Waiting on security: Finding · Review · Proposed (dismiss / accept risk) · Their reasoning · Waiting since, oldest first, since age is what makes it a queue. Open otherwise: Finding · Kind · Rating · Status · What would move it, highest rating first. Above them, how many are in each part and how many are high level or high priority. Then the step 3 question.

**The diff**, before writing: Finding · From → To · Reasoning, for the user to confirm.

**After recording**: the applied table, Finding · From → To · Reasoning recorded, then anything not applied and why, then what remains open in the review.

Offer `send-to-developer` for the message back to the team, or the shareable page via `publish-clover-artifact`.

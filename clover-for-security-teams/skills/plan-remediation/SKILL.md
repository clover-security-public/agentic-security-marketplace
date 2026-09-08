---
name: plan-remediation
description: >-
  Groups a review's or application's open findings (threats, security requirements, and questionnaire
  items) by the mitigation that closes them, so a team receives a handful of actions instead of a long
  list. Use when preparing remediation tickets, or asking what the actual plan is.
disable-model-invocation: true
---
# Plan Remediation

Sixty open findings are not sixty pieces of work.

Clover holds the data and does the analysis. This skill asks well, reads the answer correctly, and lays it out. It never derives, judges, or re-analyses on Clover's behalf.

## 1. Scope the request

Settle two things with the user before asking Clover anything:

1. **Which findings.** Either a specific set they name (particular threats, requirements, or questionnaire items, by name or id), or everything open in one review or one application. When they name an application, have Clover resolve it; when it matches several, list the candidates and let the user pick.
2. **Which kinds.** Threats, security requirements, questionnaire items, or all of them. Default to all when the user says "the findings" without qualifying, and say so.

Also note whether the plan is for the security team or for the delivery team; it changes who each action is written for.

## 2. Ask Clover

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call.

1. **The open set**: ask for the open findings in scope, of the kinds chosen, each with its kind, rating (threat level for threats, priority for requirements), status, and what it asks for, plus the true total per kind.
2. **The grouping**: ask Clover to group them by the mitigation or control that would satisfy them, across kinds, and to name each group's action. The grouping is Clover's, not this skill's: a threat, two requirements from different frameworks, and a questionnaire item routinely close on one change, and Clover is what knows that.
3. **Per group**: ask which findings each action closes, its highest rating, and who would own it.
4. **Ownership**: ask which groups are gaps in shared or pre-existing systems rather than in this change.

## 3. Read the answer

- **Every finding lands in one group or an explicit ungrouped list.** The count is how the user checks the plan.
- **Show the arithmetic**, per kind: "31 threats + 14 requirements + 2 questionnaire items → 6 actions, 3 of them high", and say when it does not reconcile.
- **Threat level and priority are different ratings.** Quote each as Clover gave it; never restate one as the other or merge them into a single scale.
- **Use Clover's totals**, and say when the plan was built against the top ratings rather than everything.
- **Keep Clover's ownership split**: an action this team cannot close is reported as such, not buried in their list.

## 4. Present it

The count line, then one block per action: Action · Closes N findings (named, with their kind) · Highest rating · Owner, ordered as Clover ranked them, then the ungrouped tail.

Offer `send-to-developer` for the message to the team, or the page via `publish-clover-artifact`.

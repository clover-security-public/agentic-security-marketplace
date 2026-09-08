---
name: show-applications-breakdown
description: >-
  Breaks down the tenant's Clover applications and ranks them by maturity (repositories, collections,
  workflows, and frameworks attached, threat model on record) and by usage (reviews created, developer
  and security team engagement in them), so the program can see which applications are set up and
  active, which are set up but dormant, and which have nothing. Use when asking how the program is
  spread across applications, what is not covered, or preparing a coverage number for leadership or an
  audit.
disable-model-invocation: true
---
# Show Applications Breakdown

Every application on record, how far each has been brought into Clover, and how much it is actually used.

Clover holds the data and does the analysis. This skill asks well, reads the answer correctly, and lays it out. It never derives, judges, or re-analyses on Clover's behalf.

## 1. Scope the request

**Sweep the whole tenant by default.** Report every application on record, and narrow to a business unit, a risk profile, or a named set only when the user asks for one.

**Settle the ranking.** Two families of signal, and the user may want one or both:

- **Maturity**: what is attached to the application. Repositories and collections, workflows, security frameworks, and whether a threat model exists.
- **Usage**: what has happened on it. Reviews created (by a workflow or by a person), reviews completed, when the last one ran, and engagement: developer actions on findings (answers, proposed dispositions) and security team actions (triage, approvals, completions).

Default to both combined, ranked **lowest first**, since the bottom of the list is where the work is; flip to highest first when the user wants to see the leaders. Say which ranking produced the table.

**Threat-model coverage is the one exception to a tenant-wide sweep.** There is no tenant-wide index of it; it is checked one application at a time, so a tenant-wide request returns empty and reads like a clean bill of health. Check it on a shortlist instead, and say that is what you did, so an unchecked application is never reported as unmodelled.

## 2. Ask Clover

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call.

**One section per turn.** Ask the items below as separate messages on the same `chat_id`; a turn carrying everything at once returns less on each.

1. **The denominator**: ask how many applications the tenant holds in total, broken down by risk profile and by business unit.
2. **Maturity, per application**: ask for the count of repositories and collections attached, the workflows attached, and the security frameworks attached, plus which applications have none of each.
3. **Usage, per application**: ask for reviews created, split into created by a workflow and created by a person, reviews completed, and the date of the most recent review; then for engagement as counts of recorded actions: developer answers and proposed dispositions, and security team triage decisions, approvals, and completions.
4. **Threat model**: ask only about the shortlist that matters most, one application at a time.
5. **The ranking**: ask Clover to rank the applications on the signals the user chose and to say what each position rests on. If Clover returns the counts without a ranking, order the table by those counts and say the order is a sort of the signals shown, not a score of Clover's.

## 3. Read the answer

- **Set up but unused is a different finding from nothing attached.** An application with repositories and workflows but no reviews is dormant; one with nothing attached was never onboarded. Keep the two apart; they call for different conversations.
- **Report gaps against risk profile**: a gap on a critical application is not the same finding as one on a low-risk application.
- **Engagement is a count of recorded actions**, not a judgement of quality. Say "12 developer actions", never "well engaged".
- **"Not found in Clover" is bounded**: it means not on record, not that the thing does not exist. Name what the sweep covered.
- **Use Clover's totals**, and say when a breakdown came back capped or paged.

## 4. Present it

A tenant-wide coverage line ("214 of 1,306 applications have never been reviewed, 31 of them high-risk; 87 have nothing attached at all"), then the ranked table: Application · Risk profile · Repos / collections · Workflows · Frameworks · Reviews (workflow / manual / total) · Developer actions · Security actions · Rank, lowest first unless the user asked otherwise. Group the rows into **nothing attached**, **set up but dormant**, and **active**, and say which checks ran tenant-wide versus on a shortlist.

Offer `start-security-review` for the top of the list, `brief-application` for any single row the user wants to open, or the page via `publish-clover-artifact`.

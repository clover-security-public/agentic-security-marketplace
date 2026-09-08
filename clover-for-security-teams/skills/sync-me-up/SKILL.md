---
name: sync-me-up
description: >-
  Briefs the current Clover user on what changed for them since they last asked: the reviews assigned
  to them that need action, what moved on their reviews, and what changed on their own applications,
  closed by a three-line tenant headline. Remembers when it last ran; the first run looks back one week.
  Use when picking Clover back up after time away, or as a morning catch-up. For the full tenant
  picture over a period, use report-security-activity instead.
disable-model-invocation: true
---
# Sync Me Up

"What do I need to look at, and what moved on my things while I was away?" in one fixed shape, so two syncs a week apart read as a series.

This is the user's view. The tenant appears only as a three-line headline at the end; the organization-wide, period report is `report-security-activity`, and this skill hands off to it rather than repeating it.

Clover holds the data and does the analysis. This skill asks well, reads the answer correctly, and lays it out. It never derives, judges, or re-analyses on Clover's behalf.

## 1. Scope the request

**Who.** Clover already knows the current user from its OAuth session, so "assigned to me" and "my applications" are Clover's to resolve. Never ask the user who they are; use the email Clover reports only as the key in the state file below.

**Since when.** The window ends now and starts at the last sync (UTC):

1. Read `~/.clover/sync-me-up.json`. It maps the user's email to their state. `last_sync` is an ISO 8601 instant in UTC, always with the `Z` suffix, never a local offset:

   ```json
   { "users": { "user@example.com": { "last_sync": "2026-08-31T06:12:00Z" } } }
   ```

2. If the file or the user's entry is missing, this is a first run: **start the window 7 days ago** and say so in the report.
3. If the user names a period ("since Monday", "last two weeks"), it overrides the stored time for this run.
4. Convert the start to an absolute UTC date and time and say it back in the first sentence with the zone stated ("since Monday 31 August, 06:12 UTC"). Pass the window to Clover in the same form.

Write the new `last_sync` as the current UTC instant, **only after the report has been presented**, never before asking Clover, so a failed or abandoned sync does not swallow the window. Create the directory and file if they do not exist; leave other users' entries untouched.

## 2. Ask Clover

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call.

**One section per turn.** Ask the items below as separate messages on the same `chat_id`, never bundled into one request. A turn carrying every section at once returns less on each of them than a turn per section does. Always give Clover the window as absolute dates, phrase the personal asks as "assigned to me" and "my applications" so Clover resolves the user itself, and ask for the true total of each population alongside any sample you bound yourself ("the 10 longest waiting").

1. **Reviews assigned to you that need action.** Ask for the reviews assigned to the user that are, in the window or still now: ready to be completed; holding findings pending security approval (dismissal or risk acceptance proposed); holding developer answers to open questions awaiting the user; or sitting on the user's step past 7 days. For each: application, the reason it needs the user, since when.
2. **What moved on your reviews.** Ask for the recorded changes in the window on the user's assigned reviews: status changes (from → to), new findings, questions answered, and who or what made each move.
3. **Your applications.** For the applications the user owns or is assigned to, ask in the window for: changes made to the application record (frameworks attached or removed, risk profile, exposure, threat model changes, ownership); reviews created, split into created by a workflow or integration and created by a person, plus the total; reviews completed; threats surfaced, mitigated, and accepted.

4. **Tenant headline.** One ask, counts only, tenant-wide in the window: reviews created (split into by a workflow and by a person) and completed; threats surfaced and mitigated; risk acceptances and dismissals approved. No names, no tables, no top-10: the detail belongs to `report-security-activity`.

## 3. Read the answer

- **Every count is Clover's**: never rounded, extrapolated, or inferred, and taken from Clover's totals rather than a count of the rows returned.
- **Activity within the window only**: a review created before the window and still open is not "created this period". Items that *need the user now* are the one exception in section 1, since they matter regardless of when they arose.
- **The headline stays a headline.** If the user asks about any tenant number, run `report-security-activity` for the same window rather than expanding the headline here; the two must never become two versions of the same report.
- **Automation is not a decision**: a status moved during re-analysis is not someone accepting or dismissing anything. Keep Clover's split between what people did and what workflows did.
- **Tracking tickets: attachment only.** Say "linked to a tracking ticket", never "the ticket is still open".
- **Nothing changed is a clean answer.** Write "no change in this window" under the section and move on; never widen the window to fill it.
- **A missing reason may be a storage limit**: long free-text values are not carried in the change record, so say "no reason is readable in the audit".
- **Absolute dates everywhere**, so the report still reads correctly when pasted somewhere next week.

## 4. Present it

The same headings, in the same order, every time. Keep every section, including empty ones, so consecutive syncs line up; empty sections carry one line. Values in monospace, labels in prose, as the product does.

```markdown
# Sync · <user name> · <start date> → <end date>
<One sentence: first run or since last sync; N items need you.>

## Needs you (N)
| Review | Application | Why it needs you | Since |
<oldest first; "Nothing needs you right now." when empty>

## Your reviews: what moved
| When | Review | What moved (from → to) | Who |
<newest first; status changes first, the rest under "also touched">

## Your applications
| Application | Changed | Reviews created (workflow / manual / total) | Completed | Threats surfaced / mitigated / accepted |

## Meanwhile, across the tenant
Reviews created `N` (`W` by workflows, `M` by people) · completed `N`
Threats surfaced `N` · mitigated `N`
Decisions: `N` risk acceptances · `N` dismissals approved
_Full picture: `report-security-activity` for this window._

_Window <start> → <end>. Next sync will start from <end>._
```

Then write `last_sync` as described in §1.

Offer `triage-review` for anything in **Needs you** that waits on an approval, `summarize-review` for a review the user wants to open, `report-security-activity` when the user wants the tenant detail, and the page via `publish-clover-artifact`. The page carries the user's own queue, so do not publish by default.

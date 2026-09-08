---
name: report-security-activity
description: >-
  Reports what the security program did over a period: reviews created and completed, and threats
  surfaced, mitigated, or accepted. Use for a weekly, monthly, or quarterly update to leadership,
  a board, or an audit.
disable-model-invocation: true
---
# Report Security Activity

What the program did over a period, in numbers that trace to real records.

Clover holds the data and does the analysis. This skill asks well, reads the answer correctly, and lays it out. It never derives, judges, or re-analyses on Clover's behalf.

## 1. Scope the request

Default to the **last 30 days** unless the user named a period. State the window in the first sentence and in the header, and convert relative periods to absolute dates so the document still means something when it is pasted somewhere next month.

This is the one org-wide, time-windowed report. For one application's current standing use `brief-application`; for the user's own plate since they last looked use `sync-me-up`, whose closing tenant headline is a three-line cut of this report and must agree with it.

## 2. Ask Clover

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call.

**One section per turn.** Ask the items below as separate messages on the same `chat_id`, never bundled into one request. A turn carrying every section at once returns less on each of them than a turn per section does, and the sections it thins are the ones with the detail worth reading.

1. **Review activity**: how many reviews were created in the window, split into created by a workflow or integration and created by a person, how many completed, and how many left in progress, broken down by application, and which outcomes are worth naming.
2. **Threat movement**: threats newly surfaced, threats mitigated, and risks explicitly accepted during the window.
3. **The decisions**: for each risk acceptance and each approved dismissal, ask who decided and the reasoning recorded.

Ask for counts *and* the handful of items worth naming: bare numbers read like a dashboard, anecdotes alone read like spin. Ask for the true total of each population and bound the sample yourself ("the 3-4 threats worth naming", "the top 10 applications"): an unbounded list crowds out the detail you wanted.

§4 sets this window against the tenant's lifetime figures, so ask for the all-time total of each measure alongside its window count. Without it that column has nothing to hold.

## 3. Read the answer

- **Every count is Clover's**: never rounded, extrapolated, or inferred.
- **Use Clover's totals**, not a count of the rows returned. The total is the finding, a named sample is illustration.
- **Activity within the window**: a review created before it and still open is not "created this period"; at most it is a watchlist line.
- **Accepted risk is a decision**, reported as what was accepted, by whom, and why, not buried among closed items.
- **No section without data.** If Clover cannot provide a section's numbers, drop the section.
- **Plain language**: name applications the way the organization does, and give a threat's consequence in a clause rather than leaning on severity jargon.

## 4. Present it

Headline a VP can repeat · by the numbers (window versus total, with reviews created shown as workflow / person / total) · reviews by application · threat movement · decisions and accepted risks.

Offer the page via `publish-clover-artifact`, and a short cut if the user names Slack or email. When an earlier edition exists, keep the same section order so consecutive reports read as a series, and show this window against the prior one.

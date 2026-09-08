---
name: send-to-developer
description: >-
  Drafts the message a security engineer sends to a developer about what was just worked through in
  this conversation, in plain language the developer can act on, usually about findings but not only.
  Approves the draft with the user, then finds a connected channel (Slack, Jira, Confluence, GitHub,
  Teams, email) and sends it on request. Use when the outcome of a session has to reach the team.
disable-model-invocation: true
---
# Send To Developer

What the security engineer tells the developer, in words the developer can act on.

This skill does not call Clover. Everything it says comes from the current conversation; it formats what is already here and sends it where the user says. It adds no findings, no ratings, and no decisions of its own.

## 1. Read the session

Work out, from the conversation so far, what the developer needs to hear. It is usually about findings, but it can be a review outcome, an answer to a question they asked, a request for evidence, a decision that was made, or a plan. Collect:

- **The subject**: the review, application, ticket, or change being discussed, with the ids and links that appeared in the session.
- **What was settled**: what was accepted, dismissed, closed, or agreed, and by whom, exactly as it stands in the conversation.
- **What is still needed**: each open item, and the one concrete next thing that would settle it.
- **The language and register of the thread** the message will land in, when the session shows it.

If the session does not contain enough to write the message, ask one question. Never fill a gap from memory or by guessing what Clover would say: a wrong status announced to a developer is worse than a question to the user.

## 2. Ask who it is for

Ask the user one thing before drafting: **is this for a specific person, or for the team?** If a person, get their name (and handle, if the user has it) so the message addresses them and can @-mention them when it is sent. If the team, address the thread. Also confirm whether the reader is a developer, a product manager, or a customer's reviewer when the session leaves it open; the same content is pitched differently for each.

## 3. Draft and approve

Write the message in the user's voice, as something they would post themselves. Rules that carry over from how findings are discussed:

- **Plain language drops jargon, not specifics.** Keep component names, the data involved, and the mechanism. Say what happens if nothing changes in a clause, not a severity label.
- **Keep what the team did answer.** A message listing only gaps reads as a rejection, and that is how threads stall. Acknowledge what was done first.
- **Announce only decisions made in this session.** A status that has not moved is described as still needing something. Never imply that something was recorded, approved, or closed unless the conversation shows it was.
- **Never soften or inflate a rating** to change how it lands; quote the one from the session.
- **One item, one block.** Several findings or asks get several short blocks with the ticket's own names for them, never one merged paragraph. Every open item ends with one concrete next step and, where known, who owns it.
- **Match the thread's language**, not the language the user spoke to you in.
- **No internal notes.** Nothing about Clover's internals, the user's private reasoning, or other teams' work leaks into a message meant for the developer.

Show the draft as one copy-pasteable block, headed by whom it addresses, with one line beneath it noting anything deliberately left out. Ask the user to approve, edit, or redirect. Iterate until they say it is good. **Nothing is sent before an explicit yes on the final text.**

## 4. Find a way to send it

Once approved, look at what is actually connected in this session: the tools available to you, not a guess. Typical connections are Slack, Atlassian (Jira and Confluence), GitHub (a PR or issue comment, via the `gh` CLI when present), Microsoft 365 or Teams, and email. For each one that exists, work out the concrete destination the session points at: the Jira ticket key, the PR number, the Slack channel or the person from step 2. A connection that exists but is not authenticated is offered as "connect and send", not hidden.

## 5. Offer the options

Present the destinations as a short list, most specific first ("comment on PROJ-482", "Slack DM to Dana", "post in #payments-eng", "paste it yourself"), and ask which one the user wants, or whether they will paste it themselves. If nothing is connected, say so plainly and hand over the block. Never send anywhere the user did not pick, and never to more than one place unless they asked for that.

## 6. Send

Send exactly the approved text: no additions, no reformatting beyond what the destination requires (Slack markdown, Jira wiki markup, an @-mention for the named person). Then report what was sent, where, and the link or permalink the service returned. If the send fails, say so with the error and hand over the paste block; do not retry to a different destination on your own.

If the message announces status changes that the session shows are not yet recorded in Clover, offer `triage-review` so the ticket and the record do not drift apart.

---
name: create-routine
description: >-
  Designs a Clover routine with the user, one question at a time, then creates it. A routine is a
  scheduled agent that reads the team's Clover data on set days and sends a summary on Slack or Teams
  or as a comment, optionally with an artifact, a report page in Clover. Use when the user wants a
  recurring report, digest or check. Creating a routine needs a Clover admin.
disable-model-invocation: true
---
# Create Routine

A routine runs unattended for weeks, so every part of it is settled with the user before it is created.

Clover runs the design: it asks the questions in its own order, checks that every application, person and channel exists, works out what the routine uses, and creates it. This skill carries the conversation between the user and Clover. It never designs, fills in, or shortens the routine on Clover's behalf.

## 1. Start the conversation

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call. Pass the user's time zone as `timeZone` on every call, read from their machine as the parameter describes, so Clover recommends a schedule in their local time.

- **Only the command**: ask Clover to create a routine, and nothing more. It opens with its first question.
- **The user described the routine**: ask Clover to create a routine, carrying their description unchanged. Clover confirms what it understood and asks the first thing it leaves open.

Never create a routine from the first message, and never add a channel, person, schedule or report item the user did not give.

## 2. Carry the questions

Clover asks one question per turn, with the answer it recommends.

- **Put each question to the user as Clover's own**, with its recommendation, unedited.
- **Send the user's answer back unchanged** on the same `chat_id`. Never answer for them, even when the answer looks obvious: a guessed channel, person or hour is a routine that sends to the wrong place for weeks.
- **A change of mind goes back too.** When the user revises an earlier answer, send it; Clover reworks the definition from the whole of it.

## 3. Confirm and create

Before creating, Clover shows the whole definition: name, schedule, what the routine uses, whether it may act on what it finds, whether each run builds an artifact, and the guidelines as they will be saved. Relay it whole, never a summary: it is what the user confirms. Send their confirmation or changes back unchanged.

Creating is a write, so it goes through Clover's approval, as `ask-clover` describes: an `approval_required` status with `pending_actions` goes through `approve_clover_actions`, a permission question in prose is answered by the user on the same `chat_id`.

## 4. Read the answer

- **Created only when Clover says so**, with when the first run starts. When Clover reports the creation declined, it says what to fix; carry the conversation on rather than retrying the approval yourself.
- **Nothing is sent while setting it up.** The first summary goes out at the first run. Never send a test message to a recipient yourself, through any connection in this session.
- **Not an admin is a final answer.** When Clover says the user cannot create routines, relay it and stop.

## 5. Present it

Relay Clover's closing reply: the routine is scheduled, when its first run starts, and its link in the Clover web app, where the team sees its runs. Offer `update-routine` to change it, turn it off, or turn it back on later.

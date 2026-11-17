---
name: update-routine
description: >-
  Changes one of the team's Clover routines with the user, one question at a time (its schedule,
  guidelines, recipients or name), or turns it off or on. Use when the user wants an existing
  recurring report, digest or check to run differently, or to pause or resume it. Changing a
  routine needs a Clover admin.
disable-model-invocation: true
---
# Update Routine

A routine runs unattended for weeks, so every change is settled with the user before it is saved.

Clover finds the routine, asks only about what changes, checks every new application, person and channel, and saves the change. This skill carries the conversation between the user and Clover. It never decides a change on Clover's behalf.

## 1. Start the conversation

One conversation: omit `chat_id` on the first call, pass the returned id back on every later call. Pass the user's time zone as `timeZone` on every call, read from their machine as the parameter describes, so schedules and run times come back in their local time.

- **Only the command**: ask Clover to list the team's routines, relay the list, and ask the user which one to change.
- **The user named the routine or the change**: send what they said unchanged. Clover finds the routine and confirms which one; when several could match, it shows them, and the user's pick goes back on the same `chat_id`.

## 2. Carry the questions

Clover asks only about what changes, one question per turn, with the answer it recommends.

- **Put each question to the user as Clover's own**, with its recommendation, unedited.
- **Send the user's answer back unchanged** on the same `chat_id`. Never answer for them, even when the answer looks obvious: a guessed channel, person or hour is a routine that sends to the wrong place for weeks.
- **Only what the user asked changes.** Never ask Clover to tidy, reword or extend the rest of the routine.

## 3. Confirm and save

Before saving, Clover shows what changes, before and after. Relay it whole, never a summary: it is what the user confirms. Send their confirmation or changes back unchanged.

Saving is a write, so it goes through Clover's approval, as `ask-clover` describes: an `approval_required` status with `pending_actions` goes through `approve_clover_actions`, a permission question in prose is answered by the user on the same `chat_id`.

## 4. Read the answer

- **Changed only when Clover says so**, with when the routine next runs, or that it is now off. When Clover reports the change declined, it says what to fix; carry the conversation on rather than retrying the approval yourself.
- **Off is not deleted.** A routine turned off keeps its history and runs again once turned back on. To remove one for good, with its run history and reports, the user asks Clover through `ask-clover`; it cannot be undone.
- **Past runs are not readable here.** Clover links to the routine's page in the Clover web app, where the team sees them.
- **Not an admin is a final answer.** When Clover says the user cannot change routines, relay it and stop.

## 5. Present it

Relay Clover's closing reply: what changed, and when the routine next runs or that it is off.

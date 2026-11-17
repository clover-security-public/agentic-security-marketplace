---
name: clover-spec-review
description: Use when a Kiro spec task is blocked with Clover Security requirements, when a `.clover-requirements.md` file or a `.kiro/steering/clover-requirements-*.md` steering file exists for the spec being worked on, or when implementing a spec that Clover has reviewed. Explains how to fold Clover's security requirements into the spec and the code instead of working around them.
---

# Working with a Clover-reviewed spec

Clover reviews a Kiro spec before implementation starts and returns the security
requirements the spec is missing. The review runs as hooks named
"Clover Security" that the developer installed separately (see the
`clover-setup` skill). If none of the files below exist and no task has been
blocked, Clover is not active in this workspace and there is nothing to do.

## Where the requirements appear

- A `*.clover-requirements.md` file in the spec directory
  (`.kiro/specs/<feature>/`), beside the spec's first file — for example
  `requirements.clover-requirements.md`.
- `.kiro/steering/clover-requirements-<feature>.md`, which Kiro includes whenever
  the agent works on that spec's files.
- The error text of a blocked task start, and the developer's next prompt.

## What to do

1. **Task blocked with security requirements.** Fold each requirement into the
   spec (`requirements.md` and `design.md`, or `spec.md`), save, then start the
   task again. Saving the revised spec sends it back to Clover for judgement.
   Do not retry the task unchanged and do not work around the block.
2. **Requirements file present.** Read it before implementing and satisfy every
   requirement in the code you write.
3. **Never edit the requirement files to get past a review.** Do not delete,
   truncate or rewrite `.clover-requirements.md` or the
   `clover-requirements-*` steering file. Clover removes them once the
   requirements are genuinely covered; a cosmetic spec edit comes back denied
   with the same requirements standing.
4. **Report what you covered.** When you have satisfied Clover requirements in
   code, list which ones and how, so the developer can verify each.

## When the developer disagrees with a requirement

Do not drop it silently. Tell the developer which requirement they want to skip
and why it matters; the decision and any exception are theirs to record in
Clover.

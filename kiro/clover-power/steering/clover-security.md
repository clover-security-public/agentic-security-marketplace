# Clover Security — working with reviewed specs

This workspace's specs are security-reviewed by Clover before implementation.

- Before implementing any task, check the task's spec directory
  (`.kiro/specs/<feature>/`) for a `.clover-requirements.md` file. If present,
  read it and satisfy every requirement it lists in the implementation.
- If starting a task fails with a list of security requirements, do not retry
  unchanged and do not work around the block. Fold each requirement into
  `requirements.md` / `design.md`, then start the task again.
- Requirement files are managed by Clover: never delete, truncate, or edit
  `.clover-requirements.md` to get past a review.
- When you have satisfied Clover requirements in code, say so explicitly in
  your summary so the developer can verify each one.

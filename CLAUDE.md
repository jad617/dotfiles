# Claude Instructions

## Git workflow — ALWAYS require explicit confirmation

- **Never push** to any branch (including `main`) unless the user explicitly says to push.
- **Never merge** a branch unless the user explicitly says to merge.
- Default behavior for all git work: make changes locally only.
- When a task is done, stop at the local commit and wait for the user to say "push", "merge", or "push and merge".

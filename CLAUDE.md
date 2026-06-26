# Claude Instructions

## Git workflow — ALWAYS require explicit confirmation

- **Never push** to any branch (including `main`) unless the user explicitly says to push.
- **Never merge** a branch unless the user explicitly says to merge.
- Default behavior for all git work: make changes locally only.
- When a task is done, stop at the local commit and wait for the user to say "push", "merge", or "push and merge".
- **"Merge to main" always means push to remote origin.** When the user says "merge" / "merge to main" (with or without "bump minor"), squash-merge into `main`, create the version tag if bumping, **and push `main` + the tag to origin** — do not stop at a local merge.
- **Always squash commits** before merging a branch into main (`git merge --squash` or rebase squash), so main history stays clean.

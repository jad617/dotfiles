# Claude Instructions

## Git workflow

- **Work on a branch, never directly on `main`.** Create one before the first commit of a task.
- **Push the working branch to origin automatically** after each commit (`git push -u origin <branch>`), so the work is never only local. No need to ask.
- **Never push to `main` and never merge** unless the user explicitly says to merge.
- When a task is done, stop at the pushed branch and wait for the user to say "merge".
- **"Merge" (or "merge to main") always means, in order:**
  1. commit and push everything left on the working branch to its remote branch;
  2. squash-merge it into `main`;
  3. **bump the minor version** (`vX.Y.Z` → `vX.(Y+1).0`, an annotated tag named like the squash commit's subject) — every merge, without being told. A **major** bump only when the user says so;
  4. push `main` + the tag to origin — never stop at a local merge.
- **Always squash commits** before merging a branch into main (`git merge --squash` or rebase squash), so main history stays clean.
- **Always delete merged branches**, locally and on origin, as the last step of a merge (check first that their content is in `main`; squash-merged branches don't look merged to git, so delete them with `git branch -D`).

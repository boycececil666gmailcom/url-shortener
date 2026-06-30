---
name: git-check-in
description: Commits changes with a summary of differences, switches GitHub accounts if necessary using gh auth switch, pushes the code, and reverts to the original account.
---

# `git-check-in` Skill Instructions

When a user asks you to execute the `git-check-in` skill, follow this procedure exactly:

1. **View Differences and Commit**
   - Run `git diff` and `git diff --staged` to see all the changes.
   - Run `git status` to see what is staged/unstaged.
   - Formulate a clear, concise commit message summarizing the differences.
   - Run `git add -A` and `git commit -m "<your_commit_message>"` to commit the changes.

2. **Check Current GitHub Account**
   - Run `gh auth status` to check the current active account.
   - Parse the output to identify the currently active GitHub account (the one marked with `Active`). Note this account name so you can switch back to it later.

3. **Check Push Access**
   - Try running `git push --dry-run` to see if the current active account has access to the repository.
   - If the push succeeds (dry run), you already have access. Skip to step 5.
   - If the push fails due to a permissions error (e.g. 403 Forbidden), proceed to step 4.

4. **Switch GitHub Account**
   - Run `gh auth status` to see the list of all available authenticated accounts.
   - Identify the correct account that likely has access to this repository.
   - Use `gh auth switch --user <correct_username>` to switch to that account.
   - Run `git push --dry-run` again to verify access.

5. **Push Changes**
   - Run `git push` to push the changes to the remote repository.

6. **Revert GitHub Account**
   - If you switched accounts in step 4, you MUST switch back to the original account you noted in step 2.
   - Run `gh auth switch --user <original_username>` to revert the active account.

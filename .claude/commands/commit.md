---
description: Stage working changes, write a best-practices commit message, commit, and push.
argument-hint: [optional intent hint, e.g. "fix for #123"]
---

Stage the relevant working changes, write a commit message that follows the rules below, commit, and push to the current branch's upstream.

## Procedure

1. Gather context. Run in parallel:
   - `git status` (no `-uall`) — see all uncommitted files
   - `git diff` and `git diff --staged` — see the actual content
   - `git log -n 20 --pretty=format:'%h %s'` — learn this repo's commit-message style (Conventional Commits? plain prose? subject case?). Match what the project already does; do not impose a new convention.
   - `git branch --show-current` — current branch
   - `git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null` — upstream, or empty if none

2. Refuse to commit obvious secrets. If the staged or about-to-be-staged content includes `.env`, `*.key`, `*.pem`, `credentials.json`, `id_rsa*`, service-account JSON, or a line that reads like an API token / private key / OAuth secret, **stop and ask the user**. Do not try to redact.

3. Stage. If the user already staged files, commit only those. Otherwise stage the modified tracked files plus any new files that clearly belong with this change. **Do not use `git add -A` or `git add .`** — list paths explicitly to avoid sweeping in editor backups, OS files, or unrelated work.

4. Write the message following these rules.

   ### Subject line
   - **Imperative mood.** "Add foo", not "Added foo" or "Adds foo". Reads as "If applied, this commit will __." Matches what `git merge`, `git revert`, and `git cherry-pick` generate.
   - **50 characters or less.** Hard cap at 72.
   - **Capitalize** the first word. **No trailing period.**
   - If recent commits use Conventional Commits (`feat:`, `fix(parser):`, `chore:`), match: `<type>[(scope)]: <description>`. Standard types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`. Otherwise write plain prose.

   ### Body (include for anything non-trivial)
   - **Blank line** between subject and body — this separator is load-bearing for `git log`, `rebase`, and tools that parse commit format.
   - **Wrap at 72 columns.**
   - Explain **what changed and why**, not **how**. The diff already shows how. The body's job is to record the motivation: the bug being fixed, the constraint being addressed, the decision being made. Future readers (including future-you, six months from now) will be searching for the *why*.
   - For Conventional Commits breaking changes: append `!` to the type/scope (`feat!:` or `feat(api)!:`) **and** add a `BREAKING CHANGE: <description>` footer.
   - Reference issues with `Closes #N` / `Fixes #N` / `Refs #N` in a footer line when applicable.

   ### Anti-patterns — do not write
   - "Update files.", "Various fixes.", "WIP." — useless six months from now.
   - A bullet list that paraphrases the diff. The diff says that already.
   - Self-referential phrasing: "as requested", "per review feedback", "addressed comments". Belongs in the PR thread, not the permanent log.
   - Marketing prose or filler. Be precise.

5. Create the commit. Pass the message via heredoc so formatting is preserved exactly:

   ```bash
   git add <explicit paths>
   git commit -m "$(cat <<'EOF'
   <subject in imperative mood>

   <body explaining why, wrapped at 72>

   Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
   EOF
   )"
   ```

   - **Never** `--no-verify` to skip hooks. If a hook fails, fix the underlying problem and make a new commit. Do **not** `--amend` after a failed hook — that would rewrite the previous commit.
   - **Never** `--amend` an existing commit unless the user explicitly asks.

6. Push.
   - If current branch is `main` or `master`, **stop and ask the user** before pushing. Direct trunk pushes are rarely intentional.
   - If the branch has no upstream, push with `git push -u origin <branch>`.
   - Otherwise, plain `git push`.
   - **Never** `--force` / `--force-with-lease` without explicit user request. If the push is rejected as non-fast-forward, stop and report — don't try to "fix" it.
   - If the repo has no remote at all, skip the push and tell the user.

7. Report the commit SHA (`git log -1 --oneline`) and the push outcome.

## Arguments

If `$ARGUMENTS` is provided, treat it as a hint about the *intent* of the change (e.g., "fix for #123", "this is the rollback of yesterday's experiment"). Use it to inform the message — but don't paste it verbatim into the subject. If empty, infer everything from the diff and recent log.

## References

The rules above are compiled from:

- Tim Pope, [A Note About Git Commit Messages](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html) — the 50/72 rule, imperative mood, the blank-line separator, "explain *what* and *why*, not *how*".
- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) — `<type>[(scope)]: <description>` format, `!` and `BREAKING CHANGE:` footer for breaking changes, the standard type vocabulary.

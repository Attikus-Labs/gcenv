---
description: Run /code-review, fix the uncovered issues, then run /commit. A one-shot quality-gate-then-commit loop.
argument-hint: [optional intent hint passed through to /commit, e.g. "fix for #123"]
---

Chain `/code-review` → fix the issues it surfaces → `/commit`. The goal is a single command that gives the developer a clean, committed checkpoint without manually reading the review file and applying fixes by hand.

This command **must not push broken code**. If any blocking issue cannot be fixed (e.g., it requires a design decision or user input), stop before committing and ask.

## Procedure

1. **Run `/code-review`** by following the procedure in `.claude/commands/code-review.md` against the default scope (current branch vs `develop`, falling back to `main`). This writes `CODE_REVIEW.md` and prints a verdict (`ship` / `iterate` / `block`).

2. **Read `CODE_REVIEW.md`** in full. Group findings by label:
   - `issue (blocking)` — **must fix**
   - `issue (non-blocking)` — **fix if low-risk and obvious**; otherwise leave for the developer
   - `suggestion` — **apply only if it's a clear improvement and small**; otherwise leave
   - `question` — **do not auto-answer**; surface to the developer at the end
   - `nitpick` — **skip by default** (per `/code-review`'s own guidance, the author should feel free to ignore)
   - `praise` — **no action**
   - `chore` — **apply if mechanical** (rebase, update changeset, update docs); otherwise surface

3. **For each finding to fix, plan and apply the change.**
   - Read the file at the cited location to understand surrounding context — do not patch blindly off the diff in `CODE_REVIEW.md`.
   - Apply the smallest change that resolves the finding. Do not bundle in unrelated cleanups.
   - If a finding is ambiguous, requires a design call, or would touch >~30 lines across multiple files, **mark it as deferred** and surface it to the developer at the end. Do not guess.
   - If applying one fix creates a new conflict with another fix, resolve them in the order: blocking → non-blocking → suggestion. The blocking fix wins; later fixes adapt.

4. **Verify the fixes.** After applying, run any project-local quality gates that exist and are fast:
   - If a lint command is present (in `package.json` scripts, a `Makefile`, or a `justfile`), run it.
   - If a test command is present and runs in under ~60s for the affected scope, run it.
   - If gates fail, fix the failure (or revert the offending fix and surface the finding as deferred). Do not `--no-verify` past a failing hook.

5. **Decide whether to commit.** Stop and ask the developer if **any** of the following are true:
   - A finding labeled `issue (blocking)` could not be fixed (deferred).
   - A lint or test gate is still failing.
   - The fixes touch a large or unfamiliar surface (>20 files or >300 lines changed by the fix step alone) — at that scale, the developer should eyeball the changes before they're committed.

   Otherwise, proceed to step 6.

6. **Show the developer a brief summary before committing:**
   - Verdict from the initial review.
   - Counts: fixed / deferred / skipped (per category).
   - The list of files modified by the fix step.
   - Any deferred findings, each with file:line and a one-line reason.

   Ask: *"Apply these fixes and commit? (yes / show diff / abort)"*. On `show diff`, print `git diff` and re-ask. On `abort`, leave the working tree as-is and stop. Do not auto-commit silently.

7. **Run `/commit`** by following the procedure in `.claude/commands/commit.md`. Pass `$ARGUMENTS` through as the intent hint if provided. The commit message should reflect the *original* change plus the review fixes — not "address review findings", which is meaningless six months from now. Example subjects:

   - Good: `Add --profile flag to gcenv switch` (the original feature, plus polish from the review, in one logical commit).
   - Bad: `Apply review fixes` / `Address CODE_REVIEW.md findings`.

   `/commit` handles staging, the message, the heredoc, and the push.

8. **Report.** Print:
   - The commit SHA (`git log -1 --oneline`).
   - The push outcome.
   - The deferred-findings list again, so the developer has it in their scrollback after the commit.
   - A reminder that `CODE_REVIEW.md` is a stale snapshot now and will be overwritten on the next `/code-review` run.

## Anti-patterns — do not do

- **Do not commit if any blocking issue is unresolved.** The whole point of the chain is that it's a quality gate. Pushing past it defeats the command.
- **Do not auto-apply nits.** `/code-review` deliberately calls them optional. Auto-applying creates churn and trains the developer to ignore the review file.
- **Do not answer `question` findings on the developer's behalf.** Questions exist because something is genuinely unclear; guessing here writes wrong code into the repo.
- **Do not bundle drive-by cleanups.** If you notice an issue that the review didn't flag, leave it. The next review pass will catch it. Scope creep makes the commit message dishonest.
- **Do not re-run `/code-review` after fixing as a "verification pass."** It's expensive and the second review will find new nits because the code changed. If the developer wants verification, they re-run the chain.
- **Do not `--amend`** the previous commit. This is a fresh commit even if the previous one was small.

## When to use this vs the underlying commands

- **Just `/code-review`** — you want to read the findings yourself and decide what to do.
- **Just `/commit`** — your work is already clean and you only need a good commit message + push.
- **`/review-and-commit`** — you want the round-trip in one shot: audit, apply the obvious fixes, commit. Best for the end of a focused work session, before opening a PR with `/create-pr`.

## References

- See `.claude/commands/code-review.md` for the review checklist and finding format.
- See `.claude/commands/commit.md` for the commit-message rules and push behavior.
- [Conventional Comments](https://conventionalcomments.org/) — the label vocabulary this command triages on.

---
description: Review the current change set against open-source code-review best practices and write the report to CODE_REVIEW.md.
argument-hint: [optional scope — PR number like "#123", a path, or empty to review the current branch vs develop]
---

Perform a structured code review of the current change set and write the findings to `CODE_REVIEW.md` at the repo root. The file is local scratch — it should be in `.gitignore` and is **never committed**. This command is for the *author* (self-review before opening a PR) and for *reviewers* (deep audit of a branch or PR before commenting on GitHub). It does not post comments anywhere.

Findings use [Conventional Comments](https://conventionalcomments.org/) labels (`praise`, `nitpick`, `suggestion`, `issue`, `question`, `thought`, `chore`) with `(blocking)` / `(non-blocking)` decorations so the author can triage at a glance.

## Procedure

1. **Determine the review scope** from `$ARGUMENTS`:
   - **Empty** → review the current branch's diff vs `develop` (or `main` if `develop` does not exist): `git diff $(git merge-base HEAD origin/develop)...HEAD`. This is the default and most common case.
   - **`#N` or a PR URL** → fetch the PR with `gh pr view N --json ...` and `gh pr diff N`. Use the PR title and body as additional context.
   - **A path** (file or directory) → review the full content of those paths as if they were new (useful for auditing a vendored library or a generated module).
   - If the scope is empty *and* the working tree has uncommitted changes, ask the user whether to include them. Default: include only committed work.

2. **Gather context** to inform the review (run in parallel):
   - `git log --oneline <base>..HEAD` — the commits being reviewed.
   - `git diff --stat <base>...HEAD` — the shape of the change.
   - `git diff <base>...HEAD` — the full diff (chunk through it; do not skim).
   - For each file substantially changed, read the full file (not just the diff) when needed to understand context — diffs lie about call sites and surrounding invariants.
   - Read `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, and the project's style/lint config if present. The review must reflect *this* project's conventions, not generic ones.

3. **Score the change against the checklist below.** For each item, decide: pass / concern / fail / not-applicable. Concerns and fails become entries in the report.

   ### Core checklist (apply to every review)

   1. **Design** — Does the change fit the existing architecture? Are new abstractions justified by current need (not speculative future use)? Does it duplicate something already in the codebase?
   2. **Functionality** — Does it do what the PR/commit claims? Are edge cases handled (empty input, large input, unicode, network failure, concurrent callers)?
   3. **Complexity** — Is the change *as simple as it can be*? Look for premature abstractions, unused parameters, dead branches, "just in case" code. Three similar lines beats a wrong abstraction.
   4. **Tests** — Are there tests for new behavior? Do they actually fail when the production code is broken (mutation-test the test mentally)? Any flaky patterns: time-of-day, network, ordering, shared global state?
   5. **Naming** — Are identifiers clear and consistent with the codebase's existing vocabulary? Any misleading names (a function called `validate` that also mutates)?
   6. **Comments and docstrings** — Do comments explain *why*, not *what*? Any stale comments left over from a previous version of the code? Any TODOs without an owner or follow-up?
   7. **Style** — Does the code follow the project's existing conventions (formatting, file layout, error idioms)? If a linter exists, would it pass?
   8. **Documentation** — Are user-facing changes reflected in the README, the CHANGELOG entry / changeset, and any relevant `--help` text? Any new public API without a doc string?
   9. **Error handling** — Errors handled at boundaries (user input, network, file I/O, third-party APIs) and *not* defensively re-validated inside trusted internal code. Are error messages actionable for the user?
   10. **Security** — Input validation at boundaries, no secrets in code or logs, no command/SQL/path injection vectors, auth checks on every privileged path, safe deserialization, dependency vulnerabilities (`npm audit` / `pip-audit` / `cargo audit` if applicable).
   11. **Performance** — Any obvious accidentally-quadratic loops, N+1 queries, unbounded memory growth, blocking I/O in a hot path? Don't micro-optimize, but flag asymptotic surprises.
   12. **Backwards compatibility** — Any breaking change to public API, config schema, on-disk format, CLI flags, environment variables, or database migrations? If yes, is the changeset marked `major` and is the migration documented?
   13. **Dependencies** — Any new dependency? Is it actively maintained, license-compatible, and worth the supply-chain surface? Could a small in-repo helper replace it?
   14. **Concurrency / parallelism** — Any shared state without synchronization, race-prone patterns, missing `await`s, leaked goroutines/tasks, deadlock risk?
   15. **Open-source hygiene** — License headers if the project uses them, contributor-experience hits (broken `make test`, new undocumented prereqs), CI changes that affect forks/external contributors.

   Skip items that genuinely don't apply to the change. Don't pad the report.

4. **Format every finding as a Conventional Comment.** Each finding has a label, an optional decoration, a location, and a body:

   ```markdown
   ### [<label> (<decoration>)] <one-line headline>
   **File:** `path/to/file.ext:LINE` (or `path/to/file.ext:LINE-LINE` for ranges; or `(general)` for cross-cutting feedback)

   <body — 1-5 sentences explaining the concern, *why* it matters, and a concrete suggestion or question. Show small code snippets for clarity.>
   ```

   Labels:
   - **`praise`** — call out something done well. **Include at least one praise per review** (per Google eng-practices: mentoring matters; surface what they did right).
   - **`issue (blocking)`** — must be fixed before merge. Correctness bug, security flaw, broken test, breaking change without migration.
   - **`issue (non-blocking)`** — real problem but doesn't block: missing test for an edge case, a poor name in a non-public API, a TODO without owner.
   - **`suggestion`** — concrete alternative the author can take or leave.
   - **`nitpick`** — pure polish (formatting, micro-naming) that the author should feel free to ignore. Use sparingly — too many nits drown the signal.
   - **`question`** — you don't understand something and want the author to clarify. Asking is cheaper than guessing.
   - **`thought`** — a musing or observation that isn't a request for action. Keep these rare.
   - **`chore`** — administrative ask (rebase, update changeset, update docs).

5. **Decide the overall verdict.** One of:
   - **`ship`** — no blocking issues; non-blocking items can be addressed in a follow-up if the author chooses.
   - **`iterate`** — has non-blocking issues worth a round of revision but no hard blockers.
   - **`block`** — has at least one `issue (blocking)`. Cannot merge as-is.

6. **Write `CODE_REVIEW.md`** at the repo root, **overwriting any previous review**. Use this exact structure:

   ```markdown
   # Code Review — <scope, e.g. "feature/foo vs develop" or "PR #123">

   - **Reviewed at:** <YYYY-MM-DD HH:MM local time>
   - **Reviewer:** Claude Code (`/code-review`)
   - **Base:** <base branch / SHA>
   - **Head:** <head branch / SHA>
   - **Files changed:** <N>   **Lines:** +<added> / -<removed>
   - **Verdict:** **<ship | iterate | block>**

   ## Summary

   <2-4 sentences. What is the change, what's the overall impression, and what is the single most important thing the author should know?>

   ## Blocking issues

   <Conventional Comment entries with `issue (blocking)`. If none: "_None._">

   ## Non-blocking issues

   <Entries with `issue (non-blocking)`. If none: "_None._">

   ## Suggestions

   <`suggestion` entries.>

   ## Questions

   <`question` entries — things the author should clarify.>

   ## Nits

   <`nitpick` entries. Keep this section short; if there are more than ~5 nits, prune to the highest-signal ones.>

   ## Praise

   <`praise` entries — at least one.>

   ## Checklist

   <One line per checklist item from step 3, marked ✅ pass / ⚠️ concern / ❌ fail / — n/a, with a one-line note for any item that isn't ✅. Example:>

   - ✅ Design
   - ✅ Functionality
   - ⚠️ Tests — new edge case in `parseProfile()` is uncovered (see Non-blocking #1)
   - ❌ Security — see Blocking #1
   - — Concurrency (n/a, single-threaded shell script)
   ...

   ## How to use this file

   This file is local scratch and is gitignored. Re-running `/code-review` overwrites it. The findings here are *advisory* — the author decides what to act on. Use `/review` to post comments to GitHub when you're ready to share with the team.
   ```

7. **Make sure `CODE_REVIEW.md` is gitignored.** If `.gitignore` does not exist, create it with `CODE_REVIEW.md`. If it exists and does not include `CODE_REVIEW.md`, append the line. Do **not** stage or commit `.gitignore` from this command — leave it as a working-tree change for the user to commit if they want.

8. **Report.** Print to the user:
   - The path (`CODE_REVIEW.md`).
   - The verdict and the count of findings per severity.
   - One sentence about the most important finding so they know whether to read the file urgently or at their leisure.

## Anti-patterns — do not do

- **Do not post anywhere.** This command writes a local file. It must not run `gh pr review`, `gh pr comment`, or any other side-effecting command. Use `/review` for that.
- **Do not nitpick to inflate the report.** Five sharp findings beat thirty noise findings. If a section would be padding, write `_None._` and move on.
- **Do not paraphrase the diff.** Saying "this function adds a parameter `x`" is useless — the diff already shows that. Comment only on what the diff *means*: correctness, design, risk.
- **Do not invent issues to seem thorough.** If the change is small and clean, the report can be small and clean. A two-line "ship — adds a flag, well-tested, no concerns" is a perfectly good review.
- **Do not impose conventions the project does not use.** If the project uses 2-space indentation and snake_case, do not flag that as a style issue. The review reflects *this* project, not your preferences.
- **Do not skip the praise section.** Per [Google's reviewer guide](https://google.github.io/eng-practices/review/reviewer/looking-for.html), recognizing what was done well is part of the job. If you genuinely cannot find anything, find something — a clean test, a clear comment, a sensible refactor — and call it out.
- **Do not commit `CODE_REVIEW.md`.** It is gitignored for a reason: reviews are conversation, not artifacts. The PR thread is the durable record.

## References

- [Google Engineering Practices — Code Review Developer Guide](https://google.github.io/eng-practices/review/) — the standard, what to look for, mentoring perspective, and the "continuous improvement, not perfection" principle.
- [Conventional Comments](https://conventionalcomments.org/) — the label vocabulary (`praise`, `nitpick`, `suggestion`, `issue`, `question`, `thought`, `chore`) and decorations (`blocking` / `non-blocking`).
- [Open Source Guides — Best Practices for Maintainers](https://opensource.guide/best-practices/) — community and contributor-experience considerations.
- [OpenSSF — Concise Guide for Evaluating Open Source Software](https://github.com/ossf/wg-best-practices-os-developers/blob/main/docs/Concise-Guide-for-Evaluating-Open-Source-Software.md) — supply-chain and dependency hygiene.

---
description: Open a PR from the current feature branch to develop, with an auto-drafted changeset for the release notes.
argument-hint: [optional intent hint, e.g. "this is a breaking rename of X"]
---

Open a pull request from the current feature branch into `develop`, and add a changeset file capturing the release-note prose for this change. The changeset will later be aggregated into `CHANGELOG.md` by `/create-release`.

This command assumes [git flow](https://nvie.com/posts/a-successful-git-branching-model/) (`feature/* → develop → release/* → main`) and [`@changesets/cli`](https://github.com/changesets/changesets).

## Procedure

1. **Gather context.** Run in parallel:
   - `git branch --show-current` — must not be `main`, `master`, `develop`, or `release/*`. Refuse and ask if it is.
   - `git status` (no `-uall`) — working tree should be clean or contain only intentional changes for this PR.
   - `git fetch origin develop main --quiet` — make sure local refs are current.
   - `git log --oneline origin/develop..HEAD` — commits unique to this branch.
   - `git diff origin/develop...HEAD --stat` and `git diff origin/develop...HEAD` — full diff vs the merge-base with develop. **This is the input you will summarize for the changeset.**
   - `ls .changeset/ 2>/dev/null` and `test -f package.json && cat package.json | grep '"name"'` — confirm Changesets is initialized.
   - `git ls-remote --exit-code --heads origin develop` — confirm `develop` exists on the remote.

2. **Refuse to proceed if preconditions fail.** Tell the user and stop:
   - On a protected branch (`main`/`master`/`develop`/`release/*`).
   - `develop` does not exist on origin → instruct: `git checkout -b develop && git push -u origin develop`.
   - No `.changeset/` directory → instruct: `npx @changesets/cli@latest init`, commit, then re-run.
   - No `package.json` → Changesets needs one to track the version. Instruct: `npm init -y` (or `pnpm init`), set `"version"` to match the project's current release, commit, then re-run.
   - Working tree dirty with unrelated work → ask which files belong in this PR.

3. **Decide the bump type from the diff.** Read the diff and classify:
   - `major` — any of: removed/renamed public API, changed function signatures users depend on, changed config-file schema in a non-additive way, changed default behavior in a way that could surprise existing users. **A `BREAKING CHANGE:` footer in any commit on this branch forces `major`.**
   - `minor` — new user-facing feature, new public API, new optional config flag, new command/flag.
   - `patch` — bug fix, perf fix, internal refactor, docs, tests, build/CI, dependency bump that is not user-visible.

   When in doubt between two levels, **pick the higher one and tell the user why** so they can downgrade if they disagree.

4. **Draft the release-note prose from the diff.** Write *for users of the project*, not for reviewers of the PR:
   - **One-line summary** (imperative, present tense, user-facing). "Add `--profile` flag to `gcenv switch`" — not "refactored switch.sh".
   - **Body** (optional, only if non-trivial): 1–4 short bullets. What's new/different from the user's perspective. If `major`, include a **Migration:** line with the exact upgrade step.
   - **Do not** paraphrase the diff line-by-line.
   - **Do not** mention internal file names, refactor scope, "as discussed", or PR/issue numbers — those belong in the commit/PR, not the changelog.
   - If `$ARGUMENTS` is provided, treat it as a hint about the change's intent and use it to inform the prose; do not paste it verbatim.

5. **Show the draft to the developer for approval.** Print the bump type, the rationale (one line), and the proposed changeset file content. Ask: *"Approve, edit, or change bump type?"* — wait for a response. Do not proceed silently.

6. **Write the changeset file.** Path: `.changeset/<kebab-slug>.md` where `<kebab-slug>` is derived from the branch name (strip `feature/`, lowercase, replace `/` and `_` with `-`). If the file already exists, append a numeric suffix.

   Format (the package name must match `package.json` `"name"`):

   ```markdown
   ---
   "<package-name>": <patch|minor|major>
   ---

   <one-line summary>

   <optional body bullets>
   ```

7. **Commit the changeset.** Do **not** sweep in unrelated working-tree changes. Stage only the changeset file:

   ```bash
   git add .changeset/<kebab-slug>.md
   git commit -m "$(cat <<'EOF'
   docs(changeset): <one-line summary>

   Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
   EOF
   )"
   ```

   Never `--no-verify`. If a hook fails, fix the underlying issue and create a new commit.

8. **Push.** If the branch has no upstream: `git push -u origin <branch>`. Otherwise plain `git push`. Never `--force` without explicit user request.

9. **Open the PR with `gh`.** Base must be `develop`. Title and body follow the same rules as `/commit`'s subject and body — explain *what* and *why*, not *how*. The body must include a **Release notes** section that mirrors the changeset (so reviewers see it without opening the file):

   ```bash
   gh pr create --base develop --title "<imperative subject, ≤72 chars>" --body "$(cat <<'EOF'
   ## Summary
   <1–3 bullets — why this change exists>

   ## Release notes
   <bump type>: <one-line summary>

   <body bullets, if any>

   ## Test plan
   - [ ] <how a reviewer verifies this works>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

10. **Report.** Print the PR URL and the bump type chosen, so the developer can sanity-check before requesting review.

## Anti-patterns — do not do

- **Do not edit `CHANGELOG.md` directly in this PR.** That's `/create-release`'s job. Editing here causes merge conflicts on every parallel PR.
- **Do not include unrelated changes** when staging the changeset commit.
- **Do not target `main`.** Always `develop`. If the user wants a hotfix, that's a different flow (`hotfix/* → main`) and is out of scope for this command.
- **Do not invent a version number.** Changesets computes the next version at release time from the accumulated bump types — your job here is only to declare the bump *type*, not the number.

## References

- [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) — the changelog format the aggregated `CHANGELOG.md` follows.
- [Changesets — Adding a changeset](https://github.com/changesets/changesets/blob/main/docs/adding-a-changeset.md) — the `.changeset/*.md` file format.
- [Semantic Versioning 2.0.0](https://semver.org/) — the rules behind `major`/`minor`/`patch`.
- [A successful Git branching model](https://nvie.com/posts/a-successful-git-branching-model/) — git flow.

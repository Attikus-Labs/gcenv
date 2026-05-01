---
description: Cut a release from develop. Aggregates pending changesets into CHANGELOG.md, bumps the version, and opens a release PR to main.
argument-hint: [optional pre-release tag, e.g. "rc.1" or "beta.0"]
---

Cut a new release from `develop`. Aggregates all `.changeset/*.md` files accumulated since the last release into a versioned `CHANGELOG.md` entry, bumps the package version, and opens a `release/vX.Y.Z → main` pull request.

After the release PR is reviewed and merged to `main`, you (or a follow-up command) must **back-merge `main` into `develop`** so that `develop` carries the new version and changelog. Instructions for the back-merge are printed at the end.

This command assumes [git flow](https://nvie.com/posts/a-successful-git-branching-model/) and [`@changesets/cli`](https://github.com/changesets/changesets).

## Procedure

1. **Gather context.** Run in parallel:
   - `git branch --show-current` — must be `develop`. Refuse otherwise.
   - `git status` (no `-uall`) — must be clean.
   - `git fetch origin develop main --quiet` — refresh refs.
   - `git rev-list --left-right --count origin/develop...HEAD` — local must be in sync with `origin/develop` (no ahead, no behind).
   - `ls .changeset/*.md 2>/dev/null | grep -v README` — must list at least one changeset.
   - `cat package.json | grep '"version"'` — current version, the floor for the bump.
   - `git ls-remote --exit-code --heads origin main` — `main` must exist.
   - `gh auth status` — `gh` must be authenticated to open the PR.

2. **Refuse to proceed if preconditions fail.** Stop and tell the user:
   - Not on `develop` → `git checkout develop && git pull`.
   - Working tree dirty → commit or stash first.
   - Out of sync with `origin/develop` → `git pull --ff-only` (or rebase if diverged).
   - No changesets → there is nothing to release; tell the user and stop.
   - Existing `release/*` branch on origin → ask whether to delete it (a stale release branch usually means a previous release was abandoned and needs cleanup).

3. **Show the release plan and get explicit confirmation.** Print:
   - Current version (from `package.json`).
   - List of pending changesets — for each, the bump type and the one-line summary.
   - Computed next version (use `npx @changesets/cli status` to compute; or describe the rule: `major` wins over `minor` wins over `patch`).
   - The pre-release tag from `$ARGUMENTS`, if provided (e.g., `1.4.0-rc.1`).

   Ask: *"Proceed with release vX.Y.Z?"* — wait for `yes`. Do not proceed silently.

4. **Create the release branch from develop.**

   ```bash
   git checkout -b release/v<X.Y.Z>
   ```

   Use the version computed in step 3. If `$ARGUMENTS` provided a pre-release tag, append it: `release/v1.4.0-rc.1`.

5. **Apply the version bump and aggregate the changelog.**

   - **Stable release:**
     ```bash
     npx @changesets/cli version
     ```
   - **Pre-release** (if `$ARGUMENTS` was provided):
     ```bash
     npx @changesets/cli pre enter <tag>
     npx @changesets/cli version
     # `pre exit` happens at the next stable release, not now
     ```

   This will:
   - Update `"version"` in `package.json`.
   - Move all `.changeset/*.md` entries into a new dated section at the top of `CHANGELOG.md`, grouped by `Major Changes` / `Minor Changes` / `Patch Changes` (Changesets' default — see Anti-patterns below if you want strict Keep-a-Changelog headings).
   - Delete the consumed `.changeset/*.md` files.

6. **Sync the version to other manifests, if any.** If the project keeps a parallel version field outside `package.json` (e.g., `.claude-plugin/plugin.json`, a `VERSION` file, a Cargo/PyPI manifest), update it to match the new `package.json` version. Detect by searching for `"version"` in known manifest files; ask before editing anything ambiguous.

7. **Show the diff to the developer for review.** Print:
   - `git diff --stat`
   - The full new section added to `CHANGELOG.md`
   - The version delta (`X.Y.Z` → `X'.Y'.Z'`)

   Ask: *"CHANGELOG looks right? Proceed to commit and push?"* — wait for confirmation. The developer may want to hand-edit the changelog prose before it ships (this is the moment).

8. **Commit and push.** Conventional commit subject so downstream tooling can recognize it:

   ```bash
   git add CHANGELOG.md package.json .changeset/ <other manifest files touched>
   git commit -m "$(cat <<'EOF'
   chore(release): v<X.Y.Z>

   Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
   EOF
   )"
   git push -u origin release/v<X.Y.Z>
   ```

   Never `--no-verify`. Never `--force`.

9. **Open the release PR.** Base is `main`:

   ```bash
   gh pr create --base main --title "Release v<X.Y.Z>" --body "$(cat <<'EOF'
   Release **v<X.Y.Z>** from `develop`.

   ## Changelog
   <paste the new CHANGELOG.md section verbatim>

   ## Post-merge checklist
   - [ ] Tag `v<X.Y.Z>` is created on `main` (CI or manual: `git tag v<X.Y.Z> && git push origin v<X.Y.Z>`).
   - [ ] Release artifacts published (if applicable).
   - [ ] **Back-merge `main` into `develop`** so develop carries the new version and changelog.

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

10. **Print the back-merge instructions.** Output exactly the commands the developer needs to run *after* the release PR is merged, so develop is left clean and ready for the next iteration:

    ```text
    Once the release PR is merged to main:

      git checkout main && git pull
      git tag v<X.Y.Z> && git push origin v<X.Y.Z>     # if not handled by CI
      git checkout develop && git pull
      git merge --no-ff main -m "chore: back-merge v<X.Y.Z> into develop"
      git push origin develop

    develop will then be up to date with main, and ready for the next feature cycle.
    ```

11. **Report.** Print the release PR URL, the new version, and the count of changesets consumed.

## Anti-patterns — do not do

- **Do not run `/create-release` from any branch other than `develop`.** Hotfixes follow a different flow (`hotfix/* → main`, then back-merge to develop) and are out of scope.
- **Do not edit `CHANGELOG.md` by hand before running `changeset version`.** The tool rewrites the file; manual edits made before will be clobbered. Hand-edit *after* step 5, before step 8.
- **Do not delete `.changeset/README.md`** if Changesets created it — it documents the format for new contributors. `changeset version` only consumes `*.md` files that have frontmatter.
- **Do not push the tag from this command.** Tagging `main` before the release PR merges would create a tag on a commit that isn't on `main` yet. Tagging belongs in the post-merge step (CI or the back-merge instructions above).
- **Do not skip step 7 (the human review step).** The whole point of the release PR pattern is that a human eyeballs the changelog before it ships. The auto-drafted prose from `/create-pr` is a starting point, not the final word.
- **Do not auto-publish to a registry from this command.** Publishing belongs in CI on tag push, gated by branch protections — not in an interactive command that runs on a developer's laptop.

## Notes on the heading style

Changesets' default `CHANGELOG.md` uses `### Major Changes` / `### Minor Changes` / `### Patch Changes`. [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) prefers `### Added` / `### Changed` / `### Deprecated` / `### Removed` / `### Fixed` / `### Security`. They are not directly compatible. Pick one and stick to it. To use the Keep-a-Changelog headings, configure `"changelog"` in `.changeset/config.json` to a custom formatter (e.g., [`@changesets/changelog-github`](https://github.com/changesets/changesets/tree/main/packages/changelog-github) with a wrapper, or a small custom module). The default is fine for most projects and is what this command assumes.

## References

- [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) — changelog format and the [Unreleased] convention.
- [Changesets — Versioning](https://github.com/changesets/changesets/blob/main/docs/command-line-options.md#version) — what `changeset version` does.
- [Changesets — Pre-releases](https://github.com/changesets/changesets/blob/main/docs/prereleases.md) — `pre enter` / `pre exit` semantics.
- [Semantic Versioning 2.0.0](https://semver.org/) — version-bump rules.
- [A successful Git branching model](https://nvie.com/posts/a-successful-git-branching-model/) — git flow, including the back-merge from `main` to `develop`.

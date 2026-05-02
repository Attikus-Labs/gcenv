# gcenv

## 0.2.0

### Minor Changes

- 66a7fc6: Handle non-TTY `gcloud auth` flows. When `gcenv use`, `gcenv login`, or `gcenv reauth` runs without a controlling TTY (Claude Code's Bash tool, CI, scripts), gcloud previously fell back silently to printing a copy-paste URL — easy to miss inside an agent transcript. gcenv now detects the case (no TTY on stdin/stdout, or `$CLAUDECODE` set) and passes `--no-launch-browser` explicitly, with a stderr banner that explains the copy-paste flow up front. Both `gcloud auth login` and `gcloud auth application-default login` are covered.

  Rebrand to `Attikus-Labs/gcenv`. The Claude Code marketplace install path is now `/plugin marketplace add Attikus-Labs/gcenv` followed by `/plugin install gcenv@gcenv`. The curl installer URL moves to `https://raw.githubusercontent.com/Attikus-Labs/gcenv/main/install.sh`. Existing users on the previous origin/path will need to re-run the installer.

  Restructure the plugin under `plugins/gcenv/` so the marketplace metadata at the repo root can host multiple plugins cleanly going forward. Internal layout (`bin/`, `hooks/`, `skills/`) is unchanged.

  Document the in-session update flow (`/plugin marketplace update gcenv` + `/reload-plugins`, or the auto-update toggle) and recommend the repo-local install scope when the plugin prompts.

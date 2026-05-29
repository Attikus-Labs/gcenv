# gcenv

## 0.3.0

### Minor Changes

- 93fb7df: Use gcloud's loopback OAuth flow for `gcenv login`/`use`/`reauth` inside Claude Code.

  - Your browser opens and the auth code is read from a `localhost` callback — no more copy-pasting a verification code back into the agent.
  - gcenv now picks the flow based on whether a browser is reachable (`open` on macOS, `xdg-open` + a display server on Linux) rather than on TTY status, and falls back to copy-paste only on truly headless hosts.
  - The `gcenv` skill now hints Claude to use a 10-minute timeout for auth commands so they aren't killed mid sign-in.

## 0.2.0

### Minor Changes

- 66a7fc6: Handle non-TTY `gcloud auth` flows. When `gcenv use`, `gcenv login`, or `gcenv reauth` runs without a controlling TTY (Claude Code's Bash tool, CI, scripts), gcloud previously fell back silently to printing a copy-paste URL — easy to miss inside an agent transcript. gcenv now detects the case (no TTY on stdin/stdout, or `$CLAUDECODE` set) and passes `--no-launch-browser` explicitly, with a stderr banner that explains the copy-paste flow up front. Both `gcloud auth login` and `gcloud auth application-default login` are covered.

  Rebrand to `Attikus-Labs/gcenv`. The Claude Code marketplace install path is now `/plugin marketplace add Attikus-Labs/gcenv` followed by `/plugin install gcenv@gcenv`. The curl installer URL moves to `https://raw.githubusercontent.com/Attikus-Labs/gcenv/main/install.sh`. Existing users on the previous origin/path will need to re-run the installer.

  Restructure the plugin under `plugins/gcenv/` so the marketplace metadata at the repo root can host multiple plugins cleanly going forward. Internal layout (`bin/`, `hooks/`, `skills/`) is unchanged.

  Document the in-session update flow (`/plugin marketplace update gcenv` + `/reload-plugins`, or the auto-update toggle) and recommend the repo-local install scope when the plugin prompts.

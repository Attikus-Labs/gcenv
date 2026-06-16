# gcenv

## 0.5.2

### Patch Changes

- cc88660: Make `gcenv login` actually open the browser inside Claude Code

  gcloud opens the OAuth page via Python's `webbrowser`, which honors `$BROWSER`. Agent shells (Claude Code) export `BROWSER=true`, which turned the launch into a silent no-op — so `gcenv login` appeared to hang with nothing opening. gcenv now forces the real OS opener (`open` on macOS, `xdg-open` on Linux) for its auth commands, so `gcenv login` pops the browser in-session with no manual prefix needed. Completes the in-Claude login fix started in 0.5.1.

## 0.5.1

### Patch Changes

- 9f23e7b: Fix `gcenv login` inside a Claude Code session

  - `gcenv` subcommands (notably `gcenv login`) no longer fail with `command not found: _gcenv_login` when invoked from Claude Code's Bash tool. gcenv now self-heals a partial shell-snapshot load by delegating to its on-PATH binary.
  - The Claude Code guidance no longer wrongly claims browser OAuth can't complete in-session. On a machine with a browser, `gcenv login` runs a loopback OAuth flow in-session (give it a 10-minute timeout); only genuinely headless environments need to hand off to another terminal.

## 0.5.0

### Minor Changes

- d532f56: Make gcenv discoverable and directly usable inside Claude Code sessions

  - Claude Code sessions now get `gcenv` on PATH plus a session-start summary of the
    active profile, so the agent invokes `gcenv` directly instead of guessing at a
    version-pinned install path.
  - `gcenv add` is now safe to run non-interactively: new `--auth`/`--no-auth` flags,
    and it no longer hangs waiting for input when there's no terminal.
  - Per-session profile isolation now works correctly in Claude Code (`gcenv claude use`
    no longer leaks across concurrent sessions), and `gcenv claude show` reports the
    same profile your commands are actually scoped to.
  - `gcenv add`/`edit` now reject malformed account/project values that could
    silently redirect the active project.

## 0.4.1

### Patch Changes

- f087f56: Fix the Claude Code plugin install during `curl | bash` (open the headless CLI, not the TUI)

  The installer called `claude /plugin marketplace add` / `claude /plugin install`. The leading slash makes `claude` treat it as an in-session slash command, so it launched the interactive plugin-manager TUI instead of installing — and the still-piped stdin fed the TUI garbage. The installer now uses the `claude plugin …` CLI subcommands, which install non-interactively.

## 0.4.0

### Minor Changes

- 37f6975: Fix the "install as a Claude Code plugin?" prompt during `curl | bash` installs

  - The installer now reads your answer from the terminal, so the plugin prompt
    actually waits for input instead of silently skipping.
  - New `GCENV_INSTALL_PLUGIN` environment variable: set `1` to install the plugin
    or `0` to skip it without being prompted (useful for CI and unattended installs).

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

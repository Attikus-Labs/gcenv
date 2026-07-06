# gcenv

## 0.6.0

### Minor Changes

- ef35ae2: Harden per-session isolation against cross-account bleed between concurrent Claude Code sessions.

  **Behavior change — the global `default.profile` is now opt-in.** Previously, a session with no per-session pin and no repo `.gcenv-profile` silently fell back to `~/.gcenv/claude/default.profile`. Because that file is machine-wide, it scoped _every_ unconfigured session — and every subagent, which carries its own session id — to one account, which is the exact cross-account bleed gcenv exists to prevent. The default profile is now consulted only when `GCENV_ALLOW_GLOBAL_DEFAULT=1` is set in the environment.

  - `gcenv claude use` now **refuses** to write the global default when it can't determine the Claude session id (previously it silently wrote `default.profile`, poisoning the fallback for every other session). Setting a machine-wide default is now an explicit, human-only `gcenv claude use --global <name>` (refused inside Claude / non-interactive shells).
  - The PreToolUse hook now **denies** global-state-mutating gcloud subcommands (`config set/unset`, `auth login`, `auth application-default login`, `auth activate-service-account`, `auth revoke`) instead of env-wrapping them and giving false "scoped" assurance — those write shared global state regardless of `CLOUDSDK_*`. Override with `GCENV_ALLOW_GLOBAL_MUTATION=1`.
  - Fixed a scoping **bypass**: a command beginning with `__GCENV_CMD=` was treated as our own executor re-invocation and passed through unscoped. The text-based recursion guard is removed entirely — the rewrite now uses a leading `env` keyword (`env __GCENV_CMD=… <hook> --exec …`), so its first token is `env`, which the matcher passes through by construction. Nothing an attacker can put in a command string asserts "I am the executor."
  - The global-mutation deny now normalizes whitespace (so `config  set` / `config<TAB>set` can't dodge it) and matches only the subcommand path (so the phrase inside a quoted value like `--description="… config set …"` isn't falsely denied).
  - Fixed an **infinite loop** in the command matcher on an assignment-only command with no trailing space (e.g. `FOO=bar`).
  - State-file and per-profile ADC writes are now **atomic** (temp + rename), so a concurrent reader in another session can't observe a half-written file.
  - New: `gcenv claude doctor` (diagnose session-id / resolution issues, incl. subagents) and `gcenv claude prune` (clear stale per-session pins). `gcenv claude show` now reports which resolution leg matched.

  Docs: the skill and README now steer toward a per-repo `.gcenv-profile` (the only cwd-based leg, so it covers subagents) for any repo where GCP identity matters.

## 0.5.4

### Patch Changes

- ba8d346: Fix the active-profile prompt badge on plain (non-oh-my-zsh) zsh setups

  - `gcenv_prompt_info` now works when you source `gcenv.sh` directly, not
    just via the oh-my-zsh plugin, so `RPROMPT='$(gcenv_prompt_info)'`
    renders the active profile on a plain zsh instead of erroring or
    printing literal text.
  - The badge renders cleanly (no stray `}` or doubled icon) and uses
    native zsh colors, so it no longer depends on oh-my-zsh's colors module.

## 0.5.3

### Patch Changes

- 6a3c5fa: Fix the prompt badge rendering as literal `$(gcenv_prompt_info)` on plain zsh

  - The installer now enables `setopt prompt_subst` alongside the `RPROMPT`
    line, so the active GCP profile badge renders on a plain zsh setup, not
    just under oh-my-zsh or Powerlevel10k.
  - Re-running the installer backfills `prompt_subst` for existing setups
    that were showing the literal text.

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

---
"gcenv": minor
---

Harden per-session isolation against cross-account bleed between concurrent Claude Code sessions.

**Behavior change — the global `default.profile` is now opt-in.** Previously, a session with no per-session pin and no repo `.gcenv-profile` silently fell back to `~/.gcenv/claude/default.profile`. Because that file is machine-wide, it scoped *every* unconfigured session — and every subagent, which carries its own session id — to one account, which is the exact cross-account bleed gcenv exists to prevent. The default profile is now consulted only when `GCENV_ALLOW_GLOBAL_DEFAULT=1` is set in the environment.

- `gcenv claude use` now **refuses** to write the global default when it can't determine the Claude session id (previously it silently wrote `default.profile`, poisoning the fallback for every other session). Setting a machine-wide default is now an explicit, human-only `gcenv claude use --global <name>` (refused inside Claude / non-interactive shells).
- The PreToolUse hook now **denies** global-state-mutating gcloud subcommands (`config set/unset`, `auth login`, `auth application-default login`, `auth activate-service-account`, `auth revoke`) instead of env-wrapping them and giving false "scoped" assurance — those write shared global state regardless of `CLOUDSDK_*`. Override with `GCENV_ALLOW_GLOBAL_MUTATION=1`.
- Fixed a scoping **bypass**: a command beginning with `__GCENV_CMD=` was treated as our own executor re-invocation and passed through unscoped; the recursion guard is now specific to the actual executor call.
- Fixed an **infinite loop** in the command matcher on an assignment-only command with no trailing space (e.g. `FOO=bar`).
- State-file and per-profile ADC writes are now **atomic** (temp + rename), so a concurrent reader in another session can't observe a half-written file.
- New: `gcenv claude doctor` (diagnose session-id / resolution issues, incl. subagents) and `gcenv claude prune` (clear stale per-session pins). `gcenv claude show` now reports which resolution leg matched.

Docs: the skill and README now steer toward a per-repo `.gcenv-profile` (the only cwd-based leg, so it covers subagents) for any repo where GCP identity matters.

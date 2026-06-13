---
"gcenv": minor
---

Make gcenv discoverable and directly usable inside Claude Code sessions

- Claude Code sessions now get `gcenv` on PATH plus a session-start summary of the
  active profile, so the agent invokes `gcenv` directly instead of guessing at a
  version-pinned install path.
- `gcenv add` is now safe to run non-interactively: new `--auth`/`--no-auth` flags,
  and it no longer hangs waiting for input when there's no terminal.
- Per-session profile isolation now works correctly in Claude Code — `gcenv claude
  use` no longer leaks across concurrent sessions — and `gcenv claude show` reports
  the same profile your commands are actually scoped to.
- `gcenv add`/`edit` now reject malformed account/project values that could
  silently redirect the active project.

---
"gcenv": patch
---

Fix `gcenv login` inside a Claude Code session

- `gcenv` subcommands (notably `gcenv login`) no longer fail with `command not found: _gcenv_login` when invoked from Claude Code's Bash tool. gcenv now self-heals a partial shell-snapshot load by delegating to its on-PATH binary.
- The Claude Code guidance no longer wrongly claims browser OAuth can't complete in-session. On a machine with a browser, `gcenv login` runs a loopback OAuth flow in-session (give it a 10-minute timeout); only genuinely headless environments need to hand off to another terminal.

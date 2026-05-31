---
"gcenv": patch
---

Fix the Claude Code plugin install during `curl | bash` (open the headless CLI, not the TUI)

The installer called `claude /plugin marketplace add` / `claude /plugin install`. The leading slash makes `claude` treat it as an in-session slash command, so it launched the interactive plugin-manager TUI instead of installing — and the still-piped stdin fed the TUI garbage. The installer now uses the `claude plugin …` CLI subcommands, which install non-interactively.

---
"gcenv": minor
---

Fix the "install as a Claude Code plugin?" prompt during `curl | bash` installs

- The installer now reads your answer from the terminal, so the plugin prompt
  actually waits for input instead of silently skipping.
- New `GCENV_INSTALL_PLUGIN` environment variable: set `1` to install the plugin
  or `0` to skip it without being prompted (useful for CI and unattended installs).

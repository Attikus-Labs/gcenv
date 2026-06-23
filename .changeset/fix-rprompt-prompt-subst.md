---
"gcenv": patch
---

Fix the prompt badge rendering as literal `$(gcenv_prompt_info)` on plain zsh

- The installer now enables `setopt prompt_subst` alongside the `RPROMPT`
  line, so the active GCP profile badge renders on a plain zsh setup, not
  just under oh-my-zsh or Powerlevel10k.
- Re-running the installer backfills `prompt_subst` for existing setups
  that were showing the literal text.

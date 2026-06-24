---
"gcenv": patch
---

Fix the active-profile prompt badge on plain (non-oh-my-zsh) zsh setups

- `gcenv_prompt_info` now works when you source `gcenv.sh` directly, not
  just via the oh-my-zsh plugin, so `RPROMPT='$(gcenv_prompt_info)'`
  renders the active profile on a plain zsh instead of erroring or
  printing literal text.
- The badge renders cleanly (no stray `}` or doubled icon) and uses
  native zsh colors, so it no longer depends on oh-my-zsh's colors module.

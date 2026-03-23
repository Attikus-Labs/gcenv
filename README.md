# gcenv

pyenv-style gcloud account/project switcher. Run different GCP accounts in different terminal tabs with full isolation.

## Install

```bash
git clone <repo-url> ~/gcenv
cd ~/gcenv
./install.sh
```

The installer detects your shell:
- **zsh + oh-my-zsh**: Symlinks as an oh-my-zsh plugin with prompt integration
- **bash / plain zsh**: Adds `source` line to your shell config

Restart your terminal after installing.

## Quick Start

```bash
# Create a profile
gcenv add prod --account=me@company.com --project=my-project

# Authenticate (opens browser)
gcenv login prod

# Switch to it in current terminal
gcenv use prod

# Open another tab — it's independent!
gcenv use staging
```

## Commands

| Command | Description |
|---------|-------------|
| `gcenv add <name>` | Create a new profile (interactive or with `--account`/`--project` flags) |
| `gcenv use <name>` | Switch current terminal to a profile |
| `gcenv list` | List all profiles (`*` marks active) |
| `gcenv current` | Show active profile details |
| `gcenv remove <name>` | Delete a profile and its credentials |
| `gcenv login <name>` | Run full auth flow (gcloud login + ADC + quota project) |
| `gcenv edit <name>` | Change account/project without re-authenticating |

## How It Works

Each terminal tab gets its own GCP context via environment variables:

- `CLOUDSDK_CORE_ACCOUNT` — overrides gcloud active account
- `CLOUDSDK_CORE_PROJECT` — overrides gcloud active project
- `CLOUDSDK_BILLING_QUOTA_PROJECT` — overrides billing quota project
- `GOOGLE_APPLICATION_CREDENTIALS` — points to per-profile ADC file

No global gcloud configuration is changed. Profiles are stored in `~/.gcenv/profiles/` and ADC credentials in `~/.gcenv/adc/`.

## Prompt Integration (oh-my-zsh)

Add `gcenv` to your plugins and add the prompt helper to your theme:

```zsh
# ~/.zshrc
plugins=(... gcenv)

# Show active profile on the right side of prompt
RPROMPT='$(gcenv_prompt_info)'
```

This shows `☁ prod` when a profile is active. Customize with:

```zsh
ZSH_THEME_GCENV_PREFIX="%{$fg[cyan]%}gcp:"
ZSH_THEME_GCENV_SUFFIX="%{$reset_color%} "
```

## Tab Completion

Completions are loaded automatically. Profile names auto-complete for `use`, `remove`, `login`, and `edit`.

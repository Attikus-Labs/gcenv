# gcenv

pyenv-style gcloud account/project switcher. Run different GCP accounts in different terminal tabs with full isolation.

## Install

```bash
git clone <repo-url> ~/gcenv
cd ~/gcenv
./install.sh
```

The installer auto-detects your setup:
- **Powerlevel10k**: Adds a `☁️ profile` segment to your right prompt
- **zsh + oh-my-zsh**: Symlinks as a plugin with prompt integration
- **bash / plain zsh**: Adds `source` line to your shell config

Restart your terminal after installing.

## Quick Start

```bash
# 1. Create a profile — follow the interactive prompts
gcenv add prod

# 2. Switch to it in current terminal
gcenv use prod

# 3. Open another tab — it's fully independent
gcenv use staging
```

## Commands

| Command | Description |
|---------|-------------|
| `gcenv add <name>` | Create a new profile. Walks you through account, project, and authentication |
| `gcenv use <name>` | Switch current terminal to a profile |
| `gcenv list` | List all profiles (`*` marks active) |
| `gcenv current` | Show active profile details |
| `gcenv login <name>` | Re-run auth for an existing profile |
| `gcenv edit <name>` | Change account/project without re-authenticating |
| `gcenv remove <name>` | Delete a profile and its credentials |

## How It Works

Each terminal tab gets its own GCP context via environment variables:

- `CLOUDSDK_CORE_ACCOUNT` — overrides gcloud active account
- `CLOUDSDK_CORE_PROJECT` — overrides gcloud active project
- `CLOUDSDK_BILLING_QUOTA_PROJECT` — overrides billing quota project
- `GOOGLE_APPLICATION_CREDENTIALS` — points to per-profile ADC file

No global gcloud configuration is changed. Profiles are stored in `~/.gcenv/profiles/` and ADC credentials in `~/.gcenv/adc/`.

## Prompt

The installer configures your prompt automatically. When a profile is active, you'll see it on the right side of your terminal:

```
~/my-project main ❯                                    ☁️ prod
```

### Manual prompt setup

If you skipped the installer or want to customize:

**Powerlevel10k** — add `gcenv` to `POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS` in `~/.p10k.zsh`.

**Oh-my-zsh (no p10k)** — add to `~/.zshrc`:
```zsh
RPROMPT='$(gcenv_prompt_info)'
```

## Tab Completion

Completions are loaded automatically. Profile names auto-complete for `use`, `remove`, `login`, and `edit`.

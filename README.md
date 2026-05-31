# gcenv

**Per-terminal and per-Claude-session GCP profile isolation.** A `gcloud` config switcher that doesn't clobber your other tabs, your other scripts, or the agent running in the next window.

```
~/my-project main ❯                                    ☁️ prod
```

## The problem

`gcloud` keeps one active account, one active project, and one Application Default Credentials file — globally, machine-wide. The moment you work on more than one GCP account, the manual flow turns into a quiet minefield:

```bash
# Morning: working on Client A
gcloud auth login me@client-a.com
gcloud config set account me@client-a.com
gcloud config set project client-a-prod
gcloud auth application-default login --billing-project=client-a-prod
# → ~/.config/gcloud/application_default_credentials.json now points at A

# Slack ping from Client B — open new tab, "real quick"
gcloud config set account me@client-b.com
gcloud config set project client-b-staging
# → both tabs now silently target B. The first tab doesn't know.

# Run the deploy script in tab 1, expecting A
./deploy.sh
# → deployed to B. Cue the chest tightening.

# Switch back: re-auth, re-set, re-ADC-login (browser dance)
gcloud config set account me@client-a.com
gcloud config set project client-a-prod
gcloud auth application-default login --billing-project=client-a-prod
```

The footguns are silent:

- `gcloud config set` is a **global** mutation. Every tab, every IDE integration, every Python script in venv #4 reads the same active config.
- ADC lives at one path: `~/.config/gcloud/application_default_credentials.json`. The last `gcloud auth application-default login` wins for every process on the machine — including a long-running script in another tab that suddenly switches accounts mid-execution.
- `CLOUDSDK_BILLING_QUOTA_PROJECT` is easy to forget. Without it, ADC user-account calls bill quota to the wrong project (and sometimes 403 against `serviceusage.services.use`).
- Two terminals. Same repo. Same `gcloud` binary. Different intent. Nothing tells you which is which.

## What gcenv does instead

Each terminal tab gets its own GCP context — set once, persists for that tab's lifetime, invisible to every other tab.

```bash
gcenv use client-a    # this tab is now Client A. Forever, until you change it.
# Other tab:
gcenv use client-b    # that tab is Client B. The first tab is unaffected.
```

Mechanism: gcenv exports `CLOUDSDK_CORE_ACCOUNT`, `CLOUDSDK_CORE_PROJECT`, `CLOUDSDK_BILLING_QUOTA_PROJECT`, and `GOOGLE_APPLICATION_CREDENTIALS` — all per-shell environment variables that `gcloud` and Google client libraries already honor. The global `gcloud config` is never touched. Each profile gets its own ADC file (`~/.gcenv/adc/<profile>.json`), so two Python scripts in two tabs run against two different accounts simultaneously, with zero risk of crossover. The active profile shows in your prompt. Stale auth tokens are detected on switch and refreshed once, interactively.

## How does this compare to other tools?

| | per-terminal isolation | per-profile ADC | per-Claude-session | activity |
|---|:---:|:---:|:---:|---|
| **gcenv** | ✅ | ✅ | ✅ | this repo |
| `gcloud config configurations` (built-in) | ❌ global | ❌ single global ADC | ❌ | official |
| [tjirsch/gcloud-switch](https://github.com/tjirsch/gcloud-switch) (Rust TUI) | ❌ activates globally | stores per-profile ADC but copies into the single global path on activate | ❌ | 0 ⭐ |
| [xgourmandin/gcloud-switch](https://github.com/xgourmandin/gcloud-switch) (Go) | ❌ global | ✅ reuses if valid | ❌ | 2 ⭐ |
| [sakebook/gsw](https://github.com/sakebook/gsw) | ✅ via `CLOUDSDK_ACTIVE_CONFIG_NAME` | ❌ shared global file | ❌ | 2 ⭐ |
| [ogerbron/gcloudctx](https://github.com/ogerbron/gcloudctx) | ❌ global (`gcloud config configurations activate`) | ❌ no ADC management | ❌ | 5 ⭐ |
| [direnv](https://direnv.net) | ✅ but per-directory, not per-tab | ✅ if you wire it | ❌ | mature |

**No actively-maintained tool combines per-terminal isolation *and* per-profile ADC files** before this one. The combination is what makes simultaneous multi-account work safe — running `terraform apply` against Client A in tab 1 while a Python script hits Client B's BigQuery in tab 2, with no shared state to fight over.

### Why not `gcloud config configurations`?

`gcloud config configurations activate prod` writes the active configuration to `~/.config/gcloud/active_config` — a single file every shell on the machine reads. Two tabs cannot be on different configurations at the same time. The whole reason gcenv exists is that this is wrong.

### Why not direnv?

direnv binds environment to a *directory*, not a *terminal*. Two tabs `cd`'d into the same monorepo get the same env — exactly the case where you want per-tab independence. direnv also doesn't run `gcloud auth login`, doesn't manage ADC files, and doesn't detect stale tokens; you'd hand-roll all of that in `.envrc`. direnv is a fine primitive to build something like gcenv on top of, but it isn't a replacement.

## Quickstart

One command:

```bash
curl -fsSL https://raw.githubusercontent.com/Attikus-Labs/gcenv/main/install.sh | bash
```

This clones gcenv to `~/.gcenv-src` (override with `GCENV_INSTALL_DIR=...`), wires up your shell, sets up the prompt segment, and offers to also install gcenv as a Claude Code plugin if `claude` is on your PATH.

The plugin prompt is interactive even over `curl | bash` (it reads from your terminal). To answer it ahead of time — e.g. in CI or an unattended install — set `GCENV_INSTALL_PLUGIN`:

```bash
curl -fsSL https://raw.githubusercontent.com/Attikus-Labs/gcenv/main/install.sh | GCENV_INSTALL_PLUGIN=1 bash   # install the plugin, no prompt
curl -fsSL https://raw.githubusercontent.com/Attikus-Labs/gcenv/main/install.sh | GCENV_INSTALL_PLUGIN=0 bash   # skip the plugin, no prompt
```

The installer auto-detects your shell:
- **Powerlevel10k** — adds a `☁️ profile` segment to your right prompt
- **zsh + oh-my-zsh** — symlinks as a plugin with prompt integration
- **bash / plain zsh** — adds a `source` line to your shell rc

Restart your terminal, then:

```bash
gcenv add prod                        # interactive: account, project, login
gcenv use prod                        # this tab is now scoped to 'prod'
gcenv list                            # see all profiles ('*' marks active in this tab)
```

> **Prefer to clone yourself?** `git clone https://github.com/Attikus-Labs/gcenv.git ~/gcenv && ~/gcenv/install.sh` does the same thing.

## Updating

Your shell sources gcenv live from the checkout the installer created (`~/.gcenv-src` by default, or `$GCENV_INSTALL_DIR` if you set one). There's no rebuild step — pulling the latest commit is enough.

```bash
git -C ~/.gcenv-src pull --ff-only
```

Open a new terminal tab (or `source ~/.zshrc` / `source ~/.bashrc`) to pick up the changes.

Re-running the curl installer works too and is idempotent — it detects the existing checkout, fast-forwards it, and re-runs the shell-rc / Powerlevel10k wiring in case any of that has changed:

```bash
curl -fsSL https://raw.githubusercontent.com/Attikus-Labs/gcenv/main/install.sh | bash
```

The Claude Code plugin is updated separately — see [Updating the plugin](#updating-the-plugin).

## Commands

| Command | Description |
|---------|-------------|
| `gcenv add <name>` | Create a new profile (interactive: account, project, optional auth) |
| `gcenv use <name>` | Switch current terminal to a profile (sets env vars, refreshes stale auth) |
| `gcenv list` | List all profiles |
| `gcenv current` | Show the active profile in this terminal |
| `gcenv login <name>` | Re-run full auth (`gcloud auth login` + ADC) for a profile |
| `gcenv reauth <name>` | Refresh user-account auth only (no ADC) |
| `gcenv edit <name>` | Change account/project without re-authenticating |
| `gcenv remove <name>` | Delete a profile and its credentials |
| `gcenv claude <subcmd>` | [Claude Code integration](#claude-code-integration) |

## Claude Code integration

`gcenv` ships as a [Claude Code](https://claude.com/claude-code) plugin. The same problems that bite humans bite agents harder: subshells, prompt injection, forgotten cleanup. A clobbered global `gcloud config` is a mistake; a clobbered global `gcloud config` set by a prompt-injection-influenced agent is a security event.

### Install

If you ran the curl-installer above and answered yes to the Claude prompt, you're done.

Otherwise, in a Claude session, install manually with two slash commands:

```
/plugin marketplace add Attikus-Labs/gcenv
/plugin install gcenv@gcenv
```

When Claude Code asks where to enable the plugin, pick **"Install for you, in this repo only (local scope)"** — that's the right default. The plugin scopes commands per Claude session anyway, so a repo-local install keeps you in control of which projects the hook is active in.

That's it. The plugin gives you:

- A `PreToolUse` hook that auto-scopes every `gcloud`, `bq`, `gsutil`, `terraform`, `kubectl`, and `helm` command Claude runs to your active profile.
- A `gcenv` skill so Claude knows when and how to call gcenv (no CLAUDE.md edits needed).
- A `/gcenv:setup` slash command that walks first-time users through profile creation.
- The `gcenv` binary on PATH inside Claude sessions.

> Eventually `gcenv` will be on the official `claude-plugins-official` marketplace for a one-command install (`claude plugin install gcenv@claude-plugins-official`). Until then, the two-command form above is the install path.

### Updating the plugin

To pull the latest gcenv into a Claude session that already has the plugin installed:

```
/plugin marketplace update gcenv
/reload-plugins
```

The first command refreshes the marketplace registry from GitHub; the second re-loads the plugin in the current session. No uninstall/reinstall needed.

Prefer set-and-forget? Open `/plugin`, go to **Marketplaces**, select **gcenv**, and toggle **Enable auto-update**. Claude Code will then pull updates at startup automatically.

If for some reason the in-place update doesn't take effect, the fallback is a full reinstall:

```
/plugin uninstall gcenv
/plugin install gcenv@gcenv
/reload-plugins
```

### Local plugin development

If you're working on the plugin itself and want Claude Code to load your uncommitted changes, swap the marketplace clone for a symlink to your working tree:

```bash
mv ~/.claude/plugins/marketplaces/gcenv ~/.claude/plugins/marketplaces/gcenv.bak
ln -s /path/to/your/gcenv-checkout ~/.claude/plugins/marketplaces/gcenv
```

Then `/reload-plugins` in any Claude session to pick up edits. Re-run it after each change to `gcenv.sh`, hooks, or skills.

To restore the normal marketplace-managed clone:

```bash
rm ~/.claude/plugins/marketplaces/gcenv
mv ~/.claude/plugins/marketplaces/gcenv.bak ~/.claude/plugins/marketplaces/gcenv
```

### Day-to-day usage

In a Claude session:

```
> "use the prod profile"
[Claude runs: gcenv claude use prod]
[hook now scopes every GCP command to prod for the rest of the session]

> "what GCP project am I on?"
[Claude runs: gcenv claude show]

> "deploy this"
[Claude runs gcloud/bq/terraform commands; hook silently scopes them to prod]
```

You set the profile once. Claude never has to remember to wrap commands. Tool-result content can't steer Claude into running raw `gcloud` against the wrong account — the hook intercepts every Bash call.

### Per-repo default with `.gcenv-profile`

Drop a `.gcenv-profile` file at the root of any repo containing one profile name:

```bash
echo prod > .gcenv-profile
```

Every Claude session in that repo now auto-scopes to `prod` with zero commands — same idea as `.python-version` or `.tool-versions`. Walks up parent directories so it works from any subfolder. `gcenv claude use <other>` still overrides it for the session.

Commit `.gcenv-profile` to share a team default; `.gitignore` it for personal use.

### Pinning a profile (high-stakes repos)

For repos where Claude should *never* leave one account (a customer-facing repo, a repo touching production), pin it at hook-install time:

```bash
gcenv claude init --pin client-a
```

Hard-codes `client-a` in `.claude/settings.json`. In-session `gcenv claude use other` is ignored — even if a malicious tool result tries to invoke it.

### Manual install (without the plugin)

If you don't use Claude Code plugins, the legacy install path still works — installs the hook + a CLAUDE.md snippet without the plugin system:

```bash
gcenv claude init                    # project-scoped (./.claude/settings.json)
gcenv claude init --user             # user-scoped (~/.claude/settings.json)
```

### `gcenv claude` subcommands

| Command | Description |
|---------|-------------|
| `gcenv claude use <profile>` | Set the active profile for the current Claude session |
| `gcenv claude show` | Show the active profile |
| `gcenv claude off` | Clear the active profile (commands run unscoped) |
| `gcenv claude run [--profile N] -- <cmd>` | Run a single command with a profile's env loaded |
| `gcenv claude init [--user] [--no-claude-md] [--pin <profile>]` | Install the hook (manual / non-plugin path) |

`jq` is required for `gcenv claude init` (`brew install jq`).

## How it works (technical)

Each profile is a tiny `.env` file in `~/.gcenv/profiles/`:

```
GCENV_ACCOUNT=me@client-a.com
GCENV_PROJECT=client-a-prod
```

`gcenv use <name>` exports four variables in the current shell:

- `CLOUDSDK_CORE_ACCOUNT` — overrides gcloud's active account
- `CLOUDSDK_CORE_PROJECT` — overrides gcloud's active project
- `CLOUDSDK_BILLING_QUOTA_PROJECT` — quota project for ADC user-account calls
- `GOOGLE_APPLICATION_CREDENTIALS` — points to `~/.gcenv/adc/<name>.json`

The global `gcloud config` is never modified. Other shells see the unchanged global config; this shell's env overrides it.

ADC files live at `~/.gcenv/adc/<profile>.json`. `gcenv login` runs `gcloud auth application-default login --billing-project=<project>` and copies the resulting credentials file into the per-profile location. The active-claude state files live at `~/.gcenv/claude/<session-id>.profile`. Both directories are mode `0700`.

Profile names must match `[A-Za-z0-9_-]+`. Names are validated before use anywhere a path or file source could be derived from them.

## Prompt

The installer configures your prompt automatically:

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

## Tab completion

Completions are loaded automatically. Profile names auto-complete for `use`, `remove`, `login`, `reauth`, `edit`, and `claude use`.

## License

MIT

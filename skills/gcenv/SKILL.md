---
name: gcenv
description: Switch GCP account/project context for the current Claude session. Use when the user mentions a GCP profile by name, asks "which project am I on?", says they want to work with a specific account/customer/environment, or when a gcloud/bq/gsutil/terraform/kubectl/helm command fails with auth errors. Also use when the user asks to set up gcenv or create a new GCP profile.
---

# gcenv — GCP profile management

`gcenv` is a per-terminal and per-Claude-session GCP profile switcher. Each profile bundles one GCP account email, one project ID, and one Application Default Credentials file. While a profile is active, `gcloud`, `bq`, `gsutil`, `terraform`, `kubectl`, and `helm` commands are automatically scoped to that profile via a `PreToolUse` hook — you do not need to wrap them.

## When to use this skill

Trigger this skill when:

- The user names a profile (`"use prod"`, `"switch to client-a"`, `"work on staging"`).
- A GCP-touching command fails with `403`, `401`, `Application Default Credentials not found`, or `serviceusage.services.use`-related errors.
- The user asks `"what GCP project am I on?"` / `"which account?"` / `"is gcenv active?"`.
- The user wants to create a new profile or set up gcenv for the first time.
- You are about to run a `gcloud auth login` or `gcloud config set` command — those commands are usually wrong inside Claude Code; use `gcenv claude use` instead.

## Active profile resolution

The active profile for this Claude session is determined in this order:

1. **Per-session state** — what the user (or you) last set via `gcenv claude use <name>`.
2. **`.gcenv-profile`** — a file in the current repo (or any ancestor directory) containing a profile name. Acts as a per-repo default.
3. **`~/.gcenv/claude/default.profile`** — a global fallback (rare).

If the hook config was installed with `--pin <profile>`, that profile overrides everything above. The user typically uses `--pin` only in customer-facing repos.

## Commands

Run these via the standard Bash tool. The `gcenv` binary is on PATH after the plugin is installed.

| Command | What it does |
|---|---|
| `gcenv list` | List all profiles. |
| `gcenv claude show` | Show which profile is active for this session. |
| `gcenv claude use <name>` | Set the active profile for the rest of this session. |
| `gcenv claude off` | Clear the active profile (commands run unscoped). |
| `gcenv add <name>` | Interactive: create a new profile (prompts for account email, picks from available projects, optionally authenticates). |
| `gcenv current` | Show what's set in this terminal's env (mostly relevant outside Claude). |

## Behavior rules

1. **Never run `gcloud auth login`, `gcloud auth application-default login`, or `gcloud config set` directly inside Claude.** Those are global, machine-wide changes that will leak out of this session and clobber other terminals. Use `gcenv` commands instead. If the user genuinely needs to re-auth, run `gcenv login <profile>` (which scopes the auth to the profile's ADC file).

2. **Confirm the active profile before destructive GCP work.** Before `gcloud compute instances delete`, `terraform apply`, `bq rm`, or any production-affecting command, run `gcenv claude show` and confirm with the user.

3. **If a GCP command fails with auth errors,** check `gcenv claude show` first. The most likely cause is no profile selected. If a profile is selected and auth still fails, suggest `gcenv login <profile>` (the user has to run this — it opens a browser).

4. **If the user asks to "switch projects",** run `gcenv claude use <name>`. Do NOT run `gcloud config set project <id>`. The two are not equivalent: `gcenv claude use` also handles the account, the billing quota project, and the ADC file; `gcloud config set` mutates global state.

5. **No profiles yet?** Run `gcenv list`. If empty, walk the user through `gcenv add <name>` (or invoke the `/gcenv:setup` skill).

## Common workflows

### "I want to work on Client A"

```
gcenv claude use client-a
gcenv claude show   # confirm: Active claude profile: client-a
```

Then run any GCP commands as normal — they auto-scope.

### "What account is this running under?"

```
gcenv claude show
```

### "This gcloud command is failing with 403"

```
gcenv claude show
# If "No active claude profile": ask the user which profile to use, then `gcenv claude use <name>`.
# If profile is set: suggest `gcenv login <profile>` to refresh credentials.
```

### "Add a new project / customer"

Invoke the `/gcenv:setup` skill, or run:

```
gcenv add <name>
```

…and follow the interactive prompts. The user must complete the browser auth step themselves.

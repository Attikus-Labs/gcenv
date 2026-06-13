---
name: setup
description: Walk the user through first-time gcenv setup — creating a profile, authenticating, and scoping the current Claude session.
disable-model-invocation: true
---

# /gcenv:setup — first-time gcenv setup

Walk the user through getting gcenv configured. This skill is user-invocable only (the user types `/gcenv:setup`), not auto-triggered.

## Steps

1. **Check existing profiles.** Run `gcenv list`. If profiles already exist, list them and ask if the user wants to (a) use an existing profile or (b) add a new one. If they pick (a), run `gcenv claude use <name>` and stop.

2. **Pick a name.** If creating a new profile, ask the user what to call it. Suggest names that map to the GCP project's role rather than its ID — e.g. `prod`, `staging`, `client-a`, `personal`. Validate that the name is `[A-Za-z0-9_-]+` (gcenv enforces this; warn early so the user doesn't get a confusing error).

3. **Ask for the account email AND the project ID.** The account is the Google account they sign in with (e.g. `me@company.com`); it is *not* the project ID. You need **both** before calling `gcenv add` — see the next step for why. If the user doesn't know the project ID, ask them to find it (the GCP console, or `gcloud projects list` in their own terminal) and give it to you. Don't try to discover it via `gcenv add` itself.

4. **Create the profile non-interactively.** Run, with all three flags:

   ```
   gcenv add <name> --account=<email> --project=<project-id> --no-auth
   ```

   `--account` and `--project` are **both required** inside Claude Code. Without `--project`, `gcenv add` falls back to an interactive project picker (or a manual "enter project ID" prompt) that can't be answered from a non-interactive Bash call — it will block until the tool times out. `--no-auth` makes gcenv create the profile and stop cleanly instead of attempting a browser sign-in. (`gcenv add` already defaults to no-auth on a non-interactive shell, but pass it explicitly so the intent is clear.)

   Never pipe answers into `gcenv add` (e.g. `printf 'y\n' | gcenv add ...`) — use the flags instead.

5. **Authenticate (the user does this, not you).** Browser OAuth cannot complete inside a Claude Code Bash call — the sandbox has no browser and may not even be able to exec `gcloud`. So do **not** run `gcenv login` / `gcenv add --auth` yourself. Instead, tell the user to run this in their **own terminal**:

   ```
   gcenv login <name>
   ```

   That opens two browser steps — `gcloud auth login` (user account) and `gcloud auth application-default login` (ADC, used by Python/Go/Terraform) — which only they can click through. Once they confirm it succeeded, continue.

6. **Scope the current session.** After the profile is created, run `gcenv claude use <name>` and confirm with `gcenv claude show`.

7. **Suggest the per-repo default (optional).** If the user is working in a project repo that should always use this profile, offer to create `.gcenv-profile` at the repo root containing `<name>`. This makes every future Claude session in that repo auto-scope without any commands. Add it to `.gitignore` if the profile is personal, or commit it if it's a team convention.

## Don't

- Don't run `gcloud auth login` yourself. That's a `gcenv login` step (or a step inside `gcenv add`).
- Don't write `gcloud config set ...` commands. Those are global and will leak out of this session.
- Don't promise authentication will work without the user's input — the OAuth flow requires their browser.

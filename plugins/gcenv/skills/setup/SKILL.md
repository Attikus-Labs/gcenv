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

5. **Authenticate with `gcenv login <name>`.** This runs two browser steps — `gcloud auth login` (user account) and `gcloud auth application-default login` (ADC, used by Python/Go/Terraform). gcenv uses loopback OAuth, so on a machine with a browser it works **in-session**: gcloud opens the browser (or prints a URL to click) and reads the code from a localhost callback — no TTY needed.

   ```
   gcenv login <name>
   ```

   - Run it with the Bash tool's `timeout: 600000` so it isn't killed while the user signs in.
   - **Confirm with the user first** — it opens a browser on their screen and overwrites the global default ADC (`~/.config/gcloud/application_default_credentials.json`).
   - First confirm `gcloud` runs here (`gcloud --version`). If `gcenv` errors with `command not found: _gcenv_*`, rerun as `command gcenv login <name>`.
   - Hand off to the user's **own terminal** only if the environment is genuinely headless (a remote container with no browser).

   The user still has to be at their browser to click through both sign-in steps. Once they confirm it succeeded, continue.

6. **Scope the current session.** After the profile is created, run `gcenv claude use <name>` and confirm with `gcenv claude show`.

7. **Suggest the per-repo default (optional).** If the user is working in a project repo that should always use this profile, offer to create `.gcenv-profile` at the repo root containing `<name>`. This makes every future Claude session in that repo auto-scope without any commands. Add it to `.gitignore` if the profile is personal, or commit it if it's a team convention.

## Don't

- Don't run *raw* `gcloud auth login` yourself — use the `gcenv login` wrapper (or `gcenv add --auth`), which isolates the credentials into the profile's ADC file.
- Don't write `gcloud config set ...` commands. Those are global and will leak out of this session.
- Authentication still needs the user at their browser to sign in — confirm with them before launching `gcenv login`, and expect to wait while they complete the two sign-in steps.

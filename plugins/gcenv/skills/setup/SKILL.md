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

3. **Ask for the account email.** This is the Google account they sign in with for that project (e.g. `me@company.com`). It is *not* the project ID.

4. **Run `gcenv add <name> --account=<email>`.** gcenv will fetch the list of projects accessible to that account and let the user choose one. If the user is not yet authenticated for that account, the listing may be empty — in that case, tell them you'll need to authenticate first. Run `gcenv add <name> --account=<email> --project=<project-id>` if the user already knows the project ID.

5. **Authenticate.** When `gcenv add` prompts `Authenticate now? (y/N)`, recommend `y`. The user will need to complete two browser steps:
   - `gcloud auth login` — for the user account
   - `gcloud auth application-default login` — for ADC (used by Python/Go/Terraform)

   You cannot complete these steps for them. Tell them clearly that browser tabs will open and they need to click through. If they decline, remind them to run `gcenv login <name>` later. **Pass `timeout: 600000` to the Bash tool** when running `gcenv add` (or `gcenv login`) — the OAuth call blocks until the user signs in, and the default 2-minute timeout is often too tight.

6. **Scope the current session.** After the profile is created, run `gcenv claude use <name>` and confirm with `gcenv claude show`.

7. **Suggest the per-repo default (optional).** If the user is working in a project repo that should always use this profile, offer to create `.gcenv-profile` at the repo root containing `<name>`. This makes every future Claude session in that repo auto-scope without any commands. Add it to `.gitignore` if the profile is personal, or commit it if it's a team convention.

## Don't

- Don't run `gcloud auth login` yourself. That's a `gcenv login` step (or a step inside `gcenv add`).
- Don't write `gcloud config set ...` commands. Those are global and will leak out of this session.
- Don't promise authentication will work without the user's input — the OAuth flow requires their browser.

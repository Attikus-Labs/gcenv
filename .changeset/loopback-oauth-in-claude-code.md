---
"gcenv": minor
---

Use gcloud's loopback OAuth flow for `gcenv login`/`use`/`reauth` inside Claude Code.

- Your browser opens and the auth code is read from a `localhost` callback — no more copy-pasting a verification code back into the agent.
- gcenv now picks the flow based on whether a browser is reachable (`open` on macOS, `xdg-open` + a display server on Linux) rather than on TTY status, and falls back to copy-paste only on truly headless hosts.
- The `gcenv` skill now hints Claude to use a 10-minute timeout for auth commands so they aren't killed mid sign-in.

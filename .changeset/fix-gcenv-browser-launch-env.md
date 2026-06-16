---
"gcenv": patch
---

Make `gcenv login` actually open the browser inside Claude Code

gcloud opens the OAuth page via Python's `webbrowser`, which honors `$BROWSER`. Agent shells (Claude Code) export `BROWSER=true`, which turned the launch into a silent no-op — so `gcenv login` appeared to hang with nothing opening. gcenv now forces the real OS opener (`open` on macOS, `xdg-open` on Linux) for its auth commands, so `gcenv login` pops the browser in-session with no manual prefix needed. Completes the in-Claude login fix started in 0.5.1.

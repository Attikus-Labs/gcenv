#!/usr/bin/env bash
# gcenv SessionStart hook for Claude Code.
#
# Fires once per Claude session (source: startup|resume|clear|compact). It does
# two things so the agent can use gcenv *natively* instead of struggling to
# discover it:
#
#   1. PATH — prepends the plugin's bin/ to PATH via $CLAUDE_ENV_FILE so the
#      bare `gcenv` command resolves in every later Bash tool call, even on a
#      plugin-only install where gcenv was never sourced into the user's shell.
#      Without this the agent hunts for, and hardcodes, a version-pinned cache
#      path (.../gcenv/0.4.1/bin/gcenv) that breaks on the next update.
#
#   2. Context — prints a short status block (active profile + how to invoke
#      gcenv + the hard rules) to stdout, which Claude Code adds to the session
#      context. The agent then knows gcenv is present and how to use it without
#      first failing a command or having to invoke the skill.
#
# Profile resolution is delegated to the PreToolUse hook's resolver (this script
# sources it), so it shares the same precedence LOGIC — there is no second,
# drifting copy. Note this is a one-shot snapshot at session start: the repo
# (.gcenv-profile) leg depends on the session's starting cwd, so if Claude later
# cd's into a differently-scoped repo, the PreToolUse hook re-resolves per
# command (and stays correct) while this block keeps reporting the start value.
# Set a session profile with `gcenv claude use <name>` for a cwd-independent pin.
#
# This hook never blocks the session and never errors out: a failure here would
# just drop the context block, so every step is defensive.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reuse the PreToolUse resolver. Sourcing it turns on `set -euo pipefail`; relax
# that immediately so one unexpected nonzero can't swallow the whole hook.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/gcenv-pretooluse.sh"
set +eu +o pipefail

GCENV_HOME="${GCENV_HOME:-$HOME/.gcenv}"
GCENV_PROFILES_DIR="$GCENV_HOME/profiles"

# --- 1. PATH injection (independent of jq and of the payload) ---------------
# CLAUDE_PLUGIN_ROOT is set by the plugin runtime and points at this version's
# checkout; bin/gcenv lives under it. Expand it now (it is NOT set in the Bash
# tool's own env); keep $PATH literal so it stacks on each command's real PATH.
if [[ -n "${CLAUDE_ENV_FILE:-}" && -n "${CLAUDE_PLUGIN_ROOT:-}" && -x "$CLAUDE_PLUGIN_ROOT/bin/gcenv" ]]; then
  # %q escapes the plugin root (expanded now) so a metacharacter in the path
  # can't break out of the export line; $PATH stays literal so it stacks on
  # whatever PATH each later command already has.
  _gcenv_path_line="$(printf 'export PATH=%s/bin:$PATH' "$(printf '%q' "$CLAUDE_PLUGIN_ROOT")")"
  # Idempotent: this hook also fires on resume/clear/compact and CLAUDE_ENV_FILE
  # may persist across those, so don't stack duplicate PATH entries.
  if ! grep -qxF "$_gcenv_path_line" "$CLAUDE_ENV_FILE" 2>/dev/null; then
    printf '%s\n' "$_gcenv_path_line" >> "$CLAUDE_ENV_FILE"
  fi
fi

# --- 2. read the SessionStart payload (best-effort) -------------------------
payload="$(cat 2>/dev/null || true)"
session_id=""
cwd=""
if command -v jq >/dev/null 2>&1 && [[ -n "$payload" ]]; then
  session_id="$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null || true)"
  cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null || true)"
fi

# Resolve the active profile exactly as the PreToolUse hook will. Its repo
# (.gcenv-profile) leg walks up from $PWD, so move into the session's cwd first.
if [[ -n "$cwd" && -d "$cwd" ]]; then
  cd "$cwd" 2>/dev/null || true
fi
profile=""
if declare -f _gcenv_hook_active_profile >/dev/null 2>&1; then
  profile="$(_gcenv_hook_active_profile "$session_id" 2>/dev/null || true)"
fi
[[ "$profile" =~ ^[A-Za-z0-9_-]+$ ]] || profile=""

# --- enumerate available profiles -------------------------------------------
profiles=()
if [[ -d "$GCENV_PROFILES_DIR" ]]; then
  for f in "$GCENV_PROFILES_DIR"/*.env; do
    [[ -e "$f" ]] || continue
    base="${f##*/}"
    base="${base%.env}"
    # Only surface valid profile names — a stray file dropped in the dir must not
    # smuggle arbitrary text into the model's context block.
    [[ "$base" =~ ^[A-Za-z0-9_-]+$ ]] || continue
    profiles+=("$base")
  done
fi

# account/project for the active profile (plain parse — never source a profile).
acct=""
proj=""
if [[ -n "$profile" && -f "$GCENV_PROFILES_DIR/$profile.env" ]]; then
  while IFS='=' read -r k v || [[ -n "$k" ]]; do
    case "$k" in
      GCENV_ACCOUNT) acct="$v" ;;
      GCENV_PROJECT) proj="$v" ;;
    esac
  done < "$GCENV_PROFILES_DIR/$profile.env"
  # gcenv add/edit reject control chars at write time, but a profile written by
  # an older gcenv (or hand-edited) might still contain them. Strip them so a
  # crafted value can't smuggle formatting/instructions into the context block.
  acct="$(printf '%s' "$acct" | tr -d '[:cntrl:]')"
  proj="$(printf '%s' "$proj" | tr -d '[:cntrl:]')"
fi

# comma-joined lists
others=""
all=""
for p in "${profiles[@]}"; do
  all+="${all:+, }$p"
  [[ "$p" == "$profile" ]] && continue
  others+="${others:+, }$p"
done

# --- 3. emit the context block, tiered by state -----------------------------
# Single-quoted printf formats keep backticks/$ literal; dynamic values are
# passed as %s args, so there is no shell expansion of the message body.
if [[ -n "$profile" ]]; then
  printf '[gcenv] GCP profile isolation is active in this Claude Code session. Invoke it as `gcenv` (it is on PATH); never hardcode a versioned cache path like .../gcenv/<ver>/bin/gcenv.\n\nActive profile: %s%s%s.\ngcloud, bq, gsutil, terraform, kubectl, and helm are auto-scoped to this profile by a PreToolUse hook — run them normally; no wrapping needed.%s\n\nRules: switch with `gcenv claude use <name>` (never `gcloud config set`). Never run `gcloud auth login` / `gcloud auth application-default login` / `gcloud config set` here — they mutate global, machine-wide state. To (re)authenticate a profile, ask the user to run `gcenv login %s` in their own terminal (browser OAuth cannot complete inside Claude). Full playbook: the `gcenv` skill.\n' \
    "$profile" "${acct:+ — account $acct}" "${proj:+, project $proj}" "${others:+ Other profiles: $others.}" "$profile"
elif (( ${#profiles[@]} > 0 )); then
  printf '[gcenv] GCP profile isolation is installed (invoke as `gcenv`). No profile is active for this session — before any gcloud/bq/gsutil/terraform/kubectl/helm command, set one with `gcenv claude use <name>`. Profiles: %s.\n' \
    "$all"
else
  printf '[gcenv] GCP profile switcher is installed (invoke as `gcenv`); no profiles exist yet. If GCP access is needed, run /gcenv:setup to create one.\n'
fi

exit 0

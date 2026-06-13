#!/usr/bin/env bash
# gcenv PreToolUse hook for Claude Code.
#
# Two modes:
#   (default) Hook mode — reads PreToolUse JSON from stdin, emits JSON to stdout
#             rewriting Bash commands that touch GCP tools to run with the
#             active gcenv profile env loaded.
#   --exec PROFILE
#             Executor mode — runs the command in $__GCENV_CMD with PROFILE's
#             env applied. Invoked by the rewritten command; not user-facing.
#
# Args (hook mode):
#   --pin PROFILE   Hard-pin the profile, ignoring any gcenv-claude state file.
#                   Useful for `gcenv claude init --pin` setups.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GCENV_LIB="$SCRIPT_DIR/../gcenv.sh"
GCENV_HOME="${GCENV_HOME:-$HOME/.gcenv}"
GCENV_CLAUDE_DIR="$GCENV_HOME/claude"

# Commands the hook scopes. First-token match only.
_gcenv_hook_match_first_token() {
  local cmd="$1"
  # Strip leading whitespace and any leading env-var assignments (e.g. FOO=1 cmd).
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  while [[ "$cmd" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    cmd="${cmd#* }"
  done
  local first="${cmd%% *}"
  first="${first##*/}"
  case "$first" in
    gcloud|gsutil|bq|terraform|kubectl|helm) return 0 ;;
    *) return 1 ;;
  esac
}

_gcenv_hook_is_recursive() {
  # Skip rewrite if Claude is running our own executor (avoids double-wrapping).
  local cmd="$1"
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  [[ "$cmd" == __GCENV_CMD=* ]]
}

# Look for a `.gcenv-profile` file in the cwd or any ancestor directory
# (analogous to how .git or .python-version are discovered). The first valid
# profile name wins. Bounds: stops at "/" or after 64 hops to avoid runaway
# walks on pathological filesystems.
_gcenv_hook_repo_profile() {
  local dir="$PWD"
  local hops=0
  while [[ -n "$dir" && "$dir" != "/" && "$hops" -lt 64 ]]; do
    if [[ -f "$dir/.gcenv-profile" ]]; then
      local profile
      profile="$(head -n1 "$dir/.gcenv-profile" 2>/dev/null | tr -d '[:space:]')"
      if [[ "$profile" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "$profile"
        return 0
      fi
      # File exists but content is malformed — stop walking; don't silently
      # fall through to a parent's .gcenv-profile that the user didn't intend.
      return 1
    fi
    dir="$(dirname "$dir")"
    hops=$((hops + 1))
  done
  return 1
}

# Resolve the profile to use for this Bash call. Priority:
#   1. Per-Claude-session state (`gcenv claude use` writes this)
#   2. .gcenv-profile in cwd or any ancestor directory
#   3. Global default file
_gcenv_hook_active_profile() {
  local sid="$1" f
  if [[ -n "$sid" ]] && [[ "$sid" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    f="$GCENV_CLAUDE_DIR/$sid.profile"
    if [[ -f "$f" ]]; then
      cat "$f"
      return 0
    fi
  fi
  if _gcenv_hook_repo_profile; then
    return 0
  fi
  f="$GCENV_CLAUDE_DIR/default.profile"
  if [[ -f "$f" ]]; then
    cat "$f"
    return 0
  fi
  return 1
}

_gcenv_hook_passthrough() {
  # Empty stdout signals "no rewrite, run command unchanged".
  exit 0
}

_gcenv_hook_main() {
  local pin=""
  while (( $# )); do
    case "$1" in
      --pin) pin="$2"; shift 2 ;;
      --pin=*) pin="${1#--pin=}"; shift ;;
      *) echo "gcenv-pretooluse: unknown arg '$1'" >&2; exit 1 ;;
    esac
  done

  if ! command -v jq >/dev/null 2>&1; then
    # No jq → silently passthrough rather than blocking the user's command.
    _gcenv_hook_passthrough
  fi

  local payload
  payload="$(cat)"
  if [[ -z "$payload" ]]; then
    _gcenv_hook_passthrough
  fi

  # Only act on Bash tool calls.
  local tool_name
  tool_name="$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null || true)"
  if [[ -n "$tool_name" && "$tool_name" != "Bash" ]]; then
    _gcenv_hook_passthrough
  fi

  local cmd session_id
  cmd="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null || true)"
  session_id="$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null || true)"

  if [[ -z "$cmd" ]]; then
    _gcenv_hook_passthrough
  fi

  if _gcenv_hook_is_recursive "$cmd"; then
    _gcenv_hook_passthrough
  fi

  if ! _gcenv_hook_match_first_token "$cmd"; then
    _gcenv_hook_passthrough
  fi

  local profile=""
  if [[ -n "$pin" ]]; then
    profile="$pin"
  else
    profile="$(_gcenv_hook_active_profile "$session_id" 2>/dev/null || true)"
  fi

  if [[ -z "$profile" ]]; then
    _gcenv_hook_passthrough
  fi

  # Validate profile name (defense-in-depth — _gcenv_apply_env will validate too).
  if [[ ! "$profile" =~ ^[A-Za-z0-9_-]+$ ]]; then
    _gcenv_hook_passthrough
  fi

  # Build the rewrite. We pass the original command via __GCENV_CMD env var
  # (printf %q ensures it's a single shell token), and re-invoke this same
  # script in --exec mode to source gcenv.sh, apply the profile env, and eval.
  local self="$SCRIPT_DIR/gcenv-pretooluse.sh"
  local orig_q profile_q self_q
  orig_q="$(printf '%q' "$cmd")"
  profile_q="$(printf '%q' "$profile")"
  self_q="$(printf '%q' "$self")"
  local rewritten="__GCENV_CMD=$orig_q $self_q --exec $profile_q"

  jq -n \
    --arg cmd "$rewritten" \
    --arg reason "gcenv: scoped to profile '$profile'" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: $reason,
        updatedInput: { command: $cmd }
      }
    }'
}

_gcenv_hook_exec() {
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    echo "gcenv-pretooluse --exec: missing profile arg" >&2
    exit 2
  fi
  if [[ ! "$profile" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "gcenv-pretooluse --exec: invalid profile '$profile'" >&2
    exit 2
  fi
  if [[ -z "${__GCENV_CMD:-}" ]]; then
    echo "gcenv-pretooluse --exec: __GCENV_CMD not set" >&2
    exit 2
  fi
  # shellcheck disable=SC1090
  source "$GCENV_LIB"
  _gcenv_apply_env "$profile" || exit 2
  local cmd="$__GCENV_CMD"
  unset __GCENV_CMD
  # Drop the strict shell options before eval so the user's command runs with
  # the same semantics it would have under Claude Code's normal Bash tool.
  # eval is intentional: $cmd is the command Claude Code was about to run
  # anyway — we're scoping its env, not introducing new attacker-controlled
  # input. Validation upstream prevents spoofed profile names.
  set +euo pipefail
  eval "$cmd"
}

main() {
  if [[ "${1:-}" == "--exec" ]]; then
    shift
    _gcenv_hook_exec "$@"
  else
    _gcenv_hook_main "$@"
  fi
}

# Only auto-run when executed directly. The SessionStart hook sources this file
# to reuse the profile-resolution helpers (_gcenv_hook_active_profile et al.) so
# that what it reports always matches what this hook will actually enforce — it
# must not trigger the PreToolUse flow on source.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

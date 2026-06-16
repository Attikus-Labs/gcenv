#!/usr/bin/env bash
# gcenv — pyenv-style gcloud account/project switcher
# Source this file in your shell config, or use the oh-my-zsh plugin.

GCENV_HOME="${GCENV_HOME:-$HOME/.gcenv}"
GCENV_PROFILES_DIR="$GCENV_HOME/profiles"
GCENV_ADC_DIR="$GCENV_HOME/adc"
GCENV_CLAUDE_DIR="$GCENV_HOME/claude"

# Resolve this script's directory so subcommands can find sibling files
# (hooks/, completions/) regardless of shell or how it's loaded.
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  GCENV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  # eval so bash never has to parse the zsh-specific %x form.
  GCENV_LIB_DIR="$(eval 'cd "$(dirname "${(%):-%x}")" 2>/dev/null && pwd')"
fi
: "${GCENV_LIB_DIR:=$PWD}"

_gcenv_ensure_dirs() {
  mkdir -p "$GCENV_PROFILES_DIR" "$GCENV_ADC_DIR" "$GCENV_CLAUDE_DIR"
  # ADC files contain refresh tokens; claude state files reveal active project.
  chmod 700 "$GCENV_ADC_DIR" "$GCENV_CLAUDE_DIR" 2>/dev/null || true
}

# Reject anything that could escape the profiles dir or smuggle shell metacharacters
# through code paths that source profile files or build paths from the name.
_gcenv_validate_name() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "gcenv: name is required" >&2
    return 1
  fi
  if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "gcenv: invalid name '$name' (allowed: letters, digits, '-', '_')" >&2
    return 1
  fi
}

# Reject control characters in values that get written into a profile file.
# A newline in an account/project value would inject a second KEY=value line;
# the last-wins parser in _gcenv_read_profile would then silently redirect the
# active project (a credential/quota-project hijack). Rejecting control chars
# also keeps these values safe to echo into the Claude Code context block.
_gcenv_validate_field() {
  local label="$1" value="$2"
  if [[ "$value" =~ [[:cntrl:]] ]]; then
    echo "gcenv: invalid $label (control characters are not allowed)" >&2
    return 1
  fi
}

# Fail fast instead of blocking on `read` when there is no interactive terminal
# (e.g. inside Claude Code's Bash tool, where stdin is not a TTY). The caller
# must supply the value via a flag/argument. Without this, an interactive prompt
# would hang the non-interactive call until it times out.
_gcenv_require_tty() {
  if [[ ! -t 0 ]]; then
    echo "gcenv: $1 — no interactive terminal here, so pass it as a flag/argument." >&2
    return 1
  fi
}

_gcenv_help() {
  cat <<'EOF'
Usage: gcenv <command> [args]

Commands:
  add <name>       Create a new gcloud profile
  use <name>       Switch current terminal to a profile
  list             List all profiles
  current          Show active profile details
  remove <name>    Delete a profile
  login <name>     Re-run full auth (gcloud + ADC) for a profile
  reauth <name>    Refresh user-account auth only (no ADC)
  edit <name>      Edit profile settings
  claude <subcmd>  Claude Code integration (run 'gcenv claude' for subcommands)
  help             Show this help message

Options for 'add':
  --account=EMAIL    GCP account email
  --project=ID       GCP project ID
  --auth             Authenticate immediately after creating the profile
  --no-auth          Skip authentication (default on a non-interactive shell,
                     e.g. inside Claude Code; run 'gcenv login <name>' later)

Examples:
  gcenv add prod --account=me@company.com --project=my-project
  gcenv add prod --account=me@company.com --project=my-project --no-auth
  gcenv use prod
  gcenv list
  gcenv claude init                # install Claude Code hook (this repo)
  gcenv claude use prod            # scope this Claude session to 'prod'
EOF
}

_gcenv_profile_path() {
  echo "$GCENV_PROFILES_DIR/$1.env"
}

_gcenv_profile_exists() {
  [[ -f "$(_gcenv_profile_path "$1")" ]]
}

# Parse a profile file into the caller's GCENV_ACCOUNT / GCENV_PROJECT vars.
# Intentionally NOT `source`-based: the profile is a trust boundary (could be
# hand-edited or copied from elsewhere) and sourcing turns any shell metachar
# in the value into code execution at use time.
_gcenv_read_profile() {
  local profile_file
  profile_file="$(_gcenv_profile_path "$1")"
  if [[ ! -f "$profile_file" ]]; then
    echo "gcenv: profile '$1' not found" >&2
    return 1
  fi
  GCENV_ACCOUNT=""
  GCENV_PROJECT=""
  local key value
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    case "$key" in
      GCENV_ACCOUNT) GCENV_ACCOUNT="$value" ;;
      GCENV_PROJECT) GCENV_PROJECT="$value" ;;
    esac
  done < "$profile_file"
}

# Export the gcloud env vars for a profile. Caller is responsible for any
# session bookkeeping (GCENV_ACTIVE, stale-token check, prompt info).
# Used by both _gcenv_use (interactive) and _gcenv_claude_run (subshell).
_gcenv_apply_env() {
  local name="$1"
  local GCENV_ACCOUNT GCENV_PROJECT
  _gcenv_read_profile "$name" || return 1

  export CLOUDSDK_CORE_ACCOUNT="$GCENV_ACCOUNT"
  export CLOUDSDK_CORE_PROJECT="$GCENV_PROJECT"
  export CLOUDSDK_BILLING_QUOTA_PROJECT="$GCENV_PROJECT"

  local adc_file="$GCENV_ADC_DIR/$name.json"
  if [[ -f "$adc_file" ]]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$adc_file"
  else
    unset GOOGLE_APPLICATION_CREDENTIALS
  fi
}

# Silently probe whether the user-account oauth token is usable.
# Redirect stdin so gcloud can't hang on an interactive reauth prompt.
_gcenv_check_auth() {
  local account="$1"
  [[ -z "$account" ]] && return 1
  gcloud auth print-access-token --account="$account" </dev/null >/dev/null 2>&1
}

# True when this host can launch a browser via the OS handler. Used to choose
# between gcloud's two non-TTY-friendly OAuth flows:
#   - loopback (default): gcloud opens the browser and reads the auth code from
#     a localhost callback. No stdin needed. Works inside Claude Code's Bash tool
#     because `open` / `xdg-open` and a localhost listener don't need a TTY.
#   - copy-paste (--no-launch-browser): gcloud prints a URL and reads the code
#     from stdin. The fallback when no browser is reachable.
_gcenv_can_launch_browser() {
  case "$OSTYPE" in
    darwin*)
      command -v open >/dev/null 2>&1
      ;;
    linux*|*bsd*)
      command -v xdg-open >/dev/null 2>&1 \
        && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

# Populate the caller's `nb_flag` array with the right gcloud auth flag for this
# environment, and print a one-time banner explaining what's about to happen.
# Caller contract: declare `local -a nb_flag=()` immediately before calling, so
# the assignment lands in caller scope and doesn't leak to shell-global state.
#
# Decision matrix:
#   TTY                              → no flag; gcloud auto-detects.
#   non-TTY, browser available       → --launch-browser; gcloud opens the
#                                      browser and reads the code from a
#                                      localhost callback. No stdin needed.
#   non-TTY, no browser (truly       → --no-launch-browser; copy-paste a URL
#   headless, e.g. remote container)   and verification code by hand.
#
# We force the flag explicitly in the non-TTY cases because gcloud's own
# detection silently falls back to copy-paste mode when stdin is not a TTY —
# which buries the URL in an agent transcript when a browser was actually
# available the whole time.
_gcenv_browser_setup() {
  if [[ -t 0 && -t 1 ]]; then
    nb_flag=()
    return 0
  fi

  if _gcenv_can_launch_browser; then
    nb_flag=(--launch-browser)
    cat >&2 <<'EOF'
gcenv: non-TTY shell with browser available — using loopback OAuth.

  Your default browser will open. Sign in to Google and the page will
  redirect back automatically — no copy-pasting a verification code.
  The browser opens once per auth step; a full login does two (user
  account + ADC). Each step blocks until sign-in completes.

EOF
    if [[ -n "${CLAUDECODE:-}" ]]; then
      cat >&2 <<'EOF'
  Inside Claude Code, the Bash tool's default 2-minute timeout may be too
  short; ask the agent to retry with a 10-minute timeout if it cuts off.

EOF
    fi
    return 0
  fi

  nb_flag=(--no-launch-browser)
  cat >&2 <<'EOF'
gcenv: non-interactive shell, no browser detected — using copy-paste flow.

  gcloud will print "Go to the following link in your browser: <url>".
  Open that URL on another device, sign in, then paste the verification
  code back here. You'll do this once per step (user auth + ADC).

EOF
}

_gcenv_add() {
  local name="" account="" project="" auth_mode=""

  # Parse arguments
  for arg in "$@"; do
    case "$arg" in
      --account=*) account="${arg#--account=}" ;;
      --project=*) project="${arg#--project=}" ;;
      --auth)      auth_mode="yes" ;;
      --no-auth)   auth_mode="no" ;;
      -*) echo "gcenv: unknown option '$arg'" >&2; return 1 ;;
      *) [[ -z "$name" ]] && name="$arg" ;;
    esac
  done

  if [[ -z "$name" ]]; then
    _gcenv_require_tty "a profile name is required" || return 1
    echo -n "Profile name: "
    read -r name
  fi

  if [[ -z "$name" ]]; then
    echo "gcenv: profile name is required" >&2
    return 1
  fi

  _gcenv_validate_name "$name" || return 1

  if _gcenv_profile_exists "$name"; then
    echo "gcenv: profile '$name' already exists. Use 'gcenv edit $name' to modify." >&2
    return 1
  fi

  if [[ -z "$account" ]]; then
    _gcenv_require_tty "--account=EMAIL is required" || return 1
    echo -n "GCP account email: "
    read -r account
  fi

  if [[ -z "$project" ]]; then
    # The project picker below is interactive (it prompts for a selection or a
    # manual ID). Don't enter it without a TTY — require --project instead.
    _gcenv_require_tty "--project=ID is required (the interactive project picker can't run here)" || return 1
    echo "Fetching projects for $account..."
    local projects=()
    while IFS= read -r line; do
      projects+=("$line")
    done < <(gcloud projects list --format="value(projectId)" --account="$account" 2>/dev/null | sort)

    # Avoid array-index access entirely: bash arrays are 0-based, zsh is
    # 1-based. Iterate with a manual counter so this works in both shells.
    if [[ ${#projects[@]} -eq 0 ]]; then
      echo "No projects found (or unable to list). Enter manually."
      echo -n "GCP project ID: "
      read -r project
    elif [[ ${#projects[@]} -eq 1 ]]; then
      project="${projects[*]}"
      echo "Only one project found: $project"
    else
      echo ""
      echo "Available projects:"
      local idx=0 p
      for p in "${projects[@]}"; do
        idx=$((idx + 1))
        printf "  %3d) %s\n" "$idx" "$p"
      done
      echo ""
      echo -n "Select project [1-${#projects[@]}]: "
      read -r selection
      if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#projects[@]} )); then
        echo "gcenv: invalid selection" >&2
        return 1
      fi
      idx=0
      for p in "${projects[@]}"; do
        idx=$((idx + 1))
        if (( idx == selection )); then
          project="$p"
          break
        fi
      done
    fi
  fi

  if [[ -z "$account" || -z "$project" ]]; then
    echo "gcenv: account and project are required" >&2
    return 1
  fi

  _gcenv_validate_field "account" "$account" || return 1
  _gcenv_validate_field "project" "$project" || return 1

  _gcenv_ensure_dirs

  cat > "$(_gcenv_profile_path "$name")" <<EOF
GCENV_ACCOUNT=$account
GCENV_PROJECT=$project
EOF

  echo "Profile '$name' created."
  echo "  Account: $account"
  echo "  Project: $project"
  echo ""

  # Decide whether to authenticate now.
  #   --auth     → always
  #   --no-auth  → never
  #   (default)  → ask, but only on an interactive TTY. Inside Claude Code (and
  #                any non-interactive caller) stdin is not a TTY, so we must not
  #                block on `read`: it would hang, or mis-consume piped input. In
  #                that case default to "no" and print the next step — the agent
  #                can then hand the browser auth to the user instead of trying
  #                (and failing) to drive OAuth itself.
  local do_auth answer
  case "$auth_mode" in
    yes) do_auth=1 ;;
    no)  do_auth=0 ;;
    *)
      if [[ -t 0 ]]; then
        echo -n "Authenticate now? (y/N) "
        read -r answer
        if [[ "$answer" =~ ^[Yy] ]]; then do_auth=1; else do_auth=0; fi
      else
        do_auth=0
      fi
      ;;
  esac

  if (( do_auth )); then
    _gcenv_login "$name"
  else
    echo "Run 'gcenv login $name' to authenticate — it opens your browser via"
    echo "loopback OAuth, so it works in a non-TTY shell (incl. Claude Code; give"
    echo "it a 10-minute timeout). Only on a truly headless host with no browser"
    echo "do you need to run it somewhere a browser is available."
  fi
}

_gcenv_use() {
  local name="$1"

  if [[ -z "$name" ]]; then
    echo "Usage: gcenv use <profile-name>" >&2
    return 1
  fi

  _gcenv_validate_name "$name" || return 1
  _gcenv_apply_env "$name" || return 1
  export GCENV_ACTIVE="$name"

  # If the user-account token is stale or missing, prompt for auth now while the
  # terminal is interactive, so later piped commands (e.g. `echo ... | gcloud
  # secrets create --data-file=-`) don't fail. Probe also returns nonzero on
  # never-authenticated accounts; in both cases we want the same recovery path.
  if ! _gcenv_check_auth "$CLOUDSDK_CORE_ACCOUNT"; then
    echo "gcenv: no usable auth token for '$CLOUDSDK_CORE_ACCOUNT', authenticating..."
    local -a nb_flag=()
    _gcenv_browser_setup
    if ! gcloud auth login "${nb_flag[@]}" "$CLOUDSDK_CORE_ACCOUNT"; then
      echo "gcenv: auth failed; run 'gcenv login $name' to retry" >&2
      return 1
    fi
  fi

  echo "Switched to '$name'"
  echo "  Account: $CLOUDSDK_CORE_ACCOUNT"
  echo "  Project: $CLOUDSDK_CORE_PROJECT"

  if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
    echo "gcenv: warning: no ADC credentials for '$name'. Run 'gcenv login $name' to set them up." >&2
  fi
}

_gcenv_list() {
  _gcenv_ensure_dirs

  local found=0 name f
  for f in "$GCENV_PROFILES_DIR"/*.env; do
    [[ -f "$f" ]] || continue
    found=1
    name="$(basename "$f" .env)"
    if [[ "$name" == "$GCENV_ACTIVE" ]]; then
      echo "* $name (active)"
    else
      echo "  $name"
    fi
  done

  if (( found == 0 )); then
    echo "No profiles found. Run 'gcenv add <name>' to create one."
  fi
}

_gcenv_current() {
  if [[ -z "$GCENV_ACTIVE" ]]; then
    echo "No active gcenv profile in this terminal."
    return 0
  fi

  echo "Active profile: $GCENV_ACTIVE"
  echo "  Account: $CLOUDSDK_CORE_ACCOUNT"
  echo "  Project: $CLOUDSDK_CORE_PROJECT"

  if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" && -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
    echo "  ADC:     $GOOGLE_APPLICATION_CREDENTIALS"
  else
    echo "  ADC:     not configured"
  fi
}

_gcenv_remove() {
  local name="$1"

  if [[ -z "$name" ]]; then
    echo "Usage: gcenv remove <profile-name>" >&2
    return 1
  fi

  _gcenv_validate_name "$name" || return 1

  if ! _gcenv_profile_exists "$name"; then
    echo "gcenv: profile '$name' not found" >&2
    return 1
  fi

  echo -n "Remove profile '$name'? (y/N) "
  read -r answer
  if [[ ! "$answer" =~ ^[Yy] ]]; then
    echo "Cancelled."
    return 0
  fi

  rm -f "$(_gcenv_profile_path "$name")"
  rm -f "$GCENV_ADC_DIR/$name.json"

  if [[ "$GCENV_ACTIVE" == "$name" ]]; then
    unset CLOUDSDK_CORE_ACCOUNT CLOUDSDK_CORE_PROJECT CLOUDSDK_BILLING_QUOTA_PROJECT
    unset GOOGLE_APPLICATION_CREDENTIALS GCENV_ACTIVE
    echo "Profile '$name' removed. Environment cleared."
  else
    echo "Profile '$name' removed."
  fi
}

_gcenv_login() {
  local name="$1"

  if [[ -z "$name" ]]; then
    echo "Usage: gcenv login <profile-name>" >&2
    return 1
  fi

  _gcenv_validate_name "$name" || return 1

  local GCENV_ACCOUNT GCENV_PROJECT
  _gcenv_read_profile "$name" || return 1

  echo "Authenticating profile '$name' ($GCENV_ACCOUNT)..."
  echo ""

  local -a nb_flag=()
  _gcenv_browser_setup

  echo "==> Step 1/2: gcloud auth login"
  if ! gcloud auth login "${nb_flag[@]}" "$GCENV_ACCOUNT"; then
    echo "gcenv: auth login failed" >&2
    return 1
  fi

  echo ""
  echo "==> Step 2/2: Application Default Credentials login"
  if ! gcloud auth application-default login "${nb_flag[@]}" --billing-project="$GCENV_PROJECT"; then
    echo "gcenv: ADC login failed" >&2
    return 1
  fi

  # Copy ADC (with quota project already set via --billing-project) to profile-specific location
  local default_adc="$HOME/.config/gcloud/application_default_credentials.json"
  if [[ -f "$default_adc" ]]; then
    cp "$default_adc" "$GCENV_ADC_DIR/$name.json"
  fi

  echo ""
  echo "Authentication complete for '$name'."
  echo "Run 'gcenv use $name' to activate this profile."
}

_gcenv_reauth() {
  local name="${1:-$GCENV_ACTIVE}"

  if [[ -z "$name" ]]; then
    echo "Usage: gcenv reauth <profile-name>" >&2
    return 1
  fi

  _gcenv_validate_name "$name" || return 1

  local GCENV_ACCOUNT GCENV_PROJECT
  _gcenv_read_profile "$name" || return 1

  echo "Reauthenticating profile '$name' ($GCENV_ACCOUNT)..."

  local -a nb_flag=()
  _gcenv_browser_setup

  if ! gcloud auth login "${nb_flag[@]}" "$GCENV_ACCOUNT"; then
    echo "gcenv: reauth failed" >&2
    return 1
  fi

  echo "Reauth complete for '$name'."
}

_gcenv_edit() {
  local name="$1"

  if [[ -z "$name" ]]; then
    echo "Usage: gcenv edit <profile-name>" >&2
    return 1
  fi

  _gcenv_validate_name "$name" || return 1

  local GCENV_ACCOUNT GCENV_PROJECT
  _gcenv_read_profile "$name" || return 1

  echo "Editing profile '$name'"
  echo "  Current account: $GCENV_ACCOUNT"
  echo -n "  New account (enter to keep): "
  read -r new_account
  [[ -n "$new_account" ]] && GCENV_ACCOUNT="$new_account"

  echo "  Current project: $GCENV_PROJECT"
  echo -n "  New project (enter to keep): "
  read -r new_project
  [[ -n "$new_project" ]] && GCENV_PROJECT="$new_project"

  _gcenv_validate_field "account" "$GCENV_ACCOUNT" || return 1
  _gcenv_validate_field "project" "$GCENV_PROJECT" || return 1

  cat > "$(_gcenv_profile_path "$name")" <<EOF
GCENV_ACCOUNT=$GCENV_ACCOUNT
GCENV_PROJECT=$GCENV_PROJECT
EOF

  echo "Profile '$name' updated."

  # If this profile is active, re-apply
  if [[ "$GCENV_ACTIVE" == "$name" ]]; then
    _gcenv_use "$name"
  fi
}

# ---------- Claude Code integration ----------

# Resolve a sanitized session id for state-file naming. Falls back to "default"
# so the same commands work outside Claude (e.g. plain shell scripts).
#
# Claude Code exposes the session id as CLAUDE_CODE_SESSION_ID. (Older/other
# names are kept as fallbacks.) This MUST match the `session_id` the PreToolUse
# hook receives in its payload — otherwise `gcenv claude use` would write a
# state file under one key while the hook looks it up under another, collapsing
# per-session isolation to the shared default.profile.
_gcenv_claude_session_id() {
  local sid="${CLAUDE_CODE_SESSION_ID:-${CLAUDECODE_SESSION_ID:-${CLAUDE_SESSION_ID:-default}}}"
  [[ "$sid" =~ ^[A-Za-z0-9_.-]+$ ]] || sid="default"
  echo "$sid"
}

_gcenv_claude_state_path() {
  echo "$GCENV_CLAUDE_DIR/$1.profile"
}

# Find a `.gcenv-profile` file in $PWD or any ancestor directory. Mirrors
# _gcenv_hook_repo_profile in hooks/gcenv-pretooluse.sh — keep the two in sync so
# `gcenv claude show` reports the same profile the hook actually enforces.
_gcenv_claude_repo_profile() {
  local dir="$PWD" hops=0 profile
  while [[ -n "$dir" && "$dir" != "/" && "$hops" -lt 64 ]]; do
    if [[ -f "$dir/.gcenv-profile" ]]; then
      profile="$(head -n1 "$dir/.gcenv-profile" 2>/dev/null | tr -d '[:space:]')"
      if [[ "$profile" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "$profile"
        return 0
      fi
      return 1
    fi
    dir="$(dirname "$dir")"
    hops=$((hops + 1))
  done
  return 1
}

# Print the active profile for a session. Resolution order MUST match the
# PreToolUse hook (_gcenv_hook_active_profile): per-session state file, then a
# repo .gcenv-profile, then the global default file. Returns 0 with the profile
# on stdout if found, 1 otherwise.
_gcenv_claude_active_profile() {
  local sid="$1" f
  f="$(_gcenv_claude_state_path "$sid")"
  if [[ -f "$f" ]]; then
    cat "$f"
    return 0
  fi
  if _gcenv_claude_repo_profile; then
    return 0
  fi
  f="$(_gcenv_claude_state_path "default")"
  if [[ -f "$f" ]]; then
    cat "$f"
    return 0
  fi
  return 1
}

_gcenv_claude_use() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: gcenv claude use <profile-name>" >&2
    return 1
  fi
  _gcenv_validate_name "$name" || return 1
  if ! _gcenv_profile_exists "$name"; then
    echo "gcenv: profile '$name' not found" >&2
    return 1
  fi
  _gcenv_ensure_dirs
  local sid
  sid="$(_gcenv_claude_session_id)"
  printf '%s\n' "$name" > "$(_gcenv_claude_state_path "$sid")"
  echo "Claude session '$sid' will use profile '$name' for GCP commands."
}

_gcenv_claude_show() {
  local sid profile
  sid="$(_gcenv_claude_session_id)"
  if profile="$(_gcenv_claude_active_profile "$sid")"; then
    echo "Active claude profile: $profile (session: $sid)"
  else
    echo "No active claude profile (session: $sid)"
  fi
}

_gcenv_claude_off() {
  local sid
  sid="$(_gcenv_claude_session_id)"
  rm -f "$(_gcenv_claude_state_path "$sid")"
  echo "Cleared active claude profile for session '$sid'."
}

# Run a single command (argv form) with a profile's env loaded in a subshell.
# Pass-through (exec without env) when no profile is set.
_gcenv_claude_run() {
  local profile=""
  while (( $# )); do
    case "$1" in
      --profile) profile="$2"; shift 2 ;;
      --profile=*) profile="${1#--profile=}"; shift ;;
      --) shift; break ;;
      *)
        echo "gcenv: unexpected argument '$1' (did you forget '--' before the command?)" >&2
        return 1
        ;;
    esac
  done

  if (( $# == 0 )); then
    echo "Usage: gcenv claude run [--profile NAME] -- <cmd> [args...]" >&2
    return 1
  fi

  if [[ -z "$profile" ]]; then
    local sid
    sid="$(_gcenv_claude_session_id)"
    profile="$(_gcenv_claude_active_profile "$sid" 2>/dev/null || true)"
  fi

  if [[ -z "$profile" ]]; then
    exec "$@"
  fi

  _gcenv_validate_name "$profile" || return 1

  (
    _gcenv_apply_env "$profile" || exit 1
    exec "$@"
  )
}

_gcenv_claude_init() {
  local scope="project"
  local with_claude_md=1
  local pin=""

  while (( $# )); do
    case "$1" in
      --user) scope="user"; shift ;;
      --project) scope="project"; shift ;;
      --no-claude-md) with_claude_md=0; shift ;;
      --pin) pin="$2"; shift 2 ;;
      --pin=*) pin="${1#--pin=}"; shift ;;
      *) echo "gcenv: unknown option '$1'" >&2; return 1 ;;
    esac
  done

  if [[ -n "$pin" ]]; then
    _gcenv_validate_name "$pin" || return 1
    if ! _gcenv_profile_exists "$pin"; then
      echo "gcenv: profile '$pin' not found" >&2
      return 1
    fi
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "gcenv: jq is required for 'gcenv claude init'." >&2
    echo "  Install via: brew install jq" >&2
    return 1
  fi

  local hook_script="$GCENV_LIB_DIR/hooks/gcenv-pretooluse.sh"
  if [[ ! -f "$hook_script" ]]; then
    echo "gcenv: hook script not found: $hook_script" >&2
    return 1
  fi
  if [[ ! -x "$hook_script" ]]; then
    chmod +x "$hook_script" 2>/dev/null || {
      echo "gcenv: hook script not executable and chmod failed: $hook_script" >&2
      return 1
    }
  fi

  local hook_command
  if [[ -n "$pin" ]]; then
    # Quote each token so jq treats it as a single command string suitable for sh -c.
    hook_command=$(printf '%q --pin %q' "$hook_script" "$pin")
  else
    hook_command=$(printf '%q' "$hook_script")
  fi

  local settings_path
  if [[ "$scope" == "user" ]]; then
    settings_path="$HOME/.claude/settings.json"
  else
    settings_path="$PWD/.claude/settings.json"
  fi

  mkdir -p "$(dirname "$settings_path")"

  local existing="{}"
  if [[ -f "$settings_path" ]]; then
    existing="$(cat "$settings_path")"
    # Validate it's actually JSON before we touch it.
    if ! jq -e . >/dev/null 2>&1 <<<"$existing"; then
      echo "gcenv: $settings_path exists but is not valid JSON; refusing to overwrite." >&2
      return 1
    fi
  fi

  local new_settings
  new_settings=$(jq --arg cmd "$hook_command" '
    .hooks //= {} |
    .hooks.PreToolUse //= [] |
    if (.hooks.PreToolUse | map((.hooks // [])[].command) | any(. == $cmd))
    then .
    else .hooks.PreToolUse += [{
      "matcher": "Bash",
      "hooks": [{"type": "command", "command": $cmd}]
    }]
    end
  ' <<<"$existing")

  if [[ -z "$new_settings" ]]; then
    echo "gcenv: failed to build settings JSON" >&2
    return 1
  fi

  if [[ "$scope" == "user" ]]; then
    echo "gcenv: about to modify $settings_path"
    echo ""
    diff <(echo "$existing" | jq -S .) <(echo "$new_settings" | jq -S .) || true
    echo ""
    echo -n "Apply this change? (y/N) "
    read -r answer
    if [[ ! "$answer" =~ ^[Yy] ]]; then
      echo "Cancelled."
      return 0
    fi
  fi

  echo "$new_settings" | jq . > "$settings_path"
  echo "Wrote $settings_path"

  if (( with_claude_md )); then
    local claude_md
    if [[ "$scope" == "user" ]]; then
      claude_md="$HOME/.claude/CLAUDE.md"
    else
      claude_md="$PWD/CLAUDE.md"
    fi
    mkdir -p "$(dirname "$claude_md")"

    if [[ -f "$claude_md" ]] && grep -qF "<!-- gcenv: managed -->" "$claude_md" 2>/dev/null; then
      echo "$claude_md already contains gcenv section; skipping."
    else
      cat >> "$claude_md" <<'GCENV_MD'

<!-- gcenv: managed -->
## GCP profile (gcenv)

When the user asks you to switch GCP profile, run `gcenv claude use <name>`. The active profile applies to subsequent `gcloud`, `gsutil`, `bq`, `terraform`, `kubectl`, and `helm` commands automatically (a PreToolUse hook injects the profile env). Use `gcenv claude show` to confirm the active profile and `gcenv claude off` to clear it. List available profiles with `gcenv list`.
<!-- /gcenv: managed -->
GCENV_MD
      echo "Updated $claude_md with gcenv section."
    fi
  fi

  if [[ -n "$pin" ]]; then
    echo "Hook pinned to profile '$pin'. In-session 'gcenv claude use' will be ignored."
  else
    echo "Run 'gcenv claude use <profile>' inside Claude to scope GCP commands."
  fi
}

_gcenv_claude() {
  local sub="${1:-help}"
  shift 2>/dev/null
  case "$sub" in
    use)   _gcenv_claude_use "$@" ;;
    show)  _gcenv_claude_show ;;
    off)   _gcenv_claude_off ;;
    run)   _gcenv_claude_run "$@" ;;
    init)  _gcenv_claude_init "$@" ;;
    help|--help|-h|*)
      cat <<'EOF'
Usage: gcenv claude <subcommand>

  use <profile>             Set the active profile for this Claude session
  show                      Show the active profile
  off                       Clear the active profile
  run [--profile N] -- CMD  Run a single command with profile env loaded
  init [--user] [--no-claude-md] [--pin <profile>]
                            Install the Claude Code PreToolUse hook
EOF
      ;;
  esac
}

gcenv() {
  # Self-heal a partial load. Claude Code snapshots the user's interactive shell
  # to seed its Bash tool, but the snapshot captures this public `gcenv` function
  # WITHOUT the _gcenv_* helpers it calls — so a bare `gcenv <subcmd>` there dies
  # with "command not found: _gcenv_login". When a helper is missing, delegate to
  # the on-PATH binary (bin/gcenv, which the SessionStart hook prepends to PATH);
  # it sources gcenv.sh fresh, defining every helper, then runs the command. In a
  # normal terminal the helpers are present, so this guard never fires.
  if ! typeset -f _gcenv_read_profile >/dev/null 2>&1; then
    command gcenv "$@"
    return
  fi

  local command="${1:-help}"
  shift 2>/dev/null

  case "$command" in
    add)     _gcenv_add "$@" ;;
    use)     _gcenv_use "$@" ;;
    list|ls) _gcenv_list ;;
    current) _gcenv_current ;;
    remove|rm) _gcenv_remove "$@" ;;
    login)   _gcenv_login "$@" ;;
    reauth)  _gcenv_reauth "$@" ;;
    edit)    _gcenv_edit "$@" ;;
    claude)  _gcenv_claude "$@" ;;
    help|--help|-h) _gcenv_help ;;
    *)
      echo "gcenv: unknown command '$command'" >&2
      _gcenv_help
      return 1
      ;;
  esac
}

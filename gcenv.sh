#!/usr/bin/env bash
# gcenv — pyenv-style gcloud account/project switcher
# Source this file in your shell config, or use the oh-my-zsh plugin.

GCENV_HOME="${GCENV_HOME:-$HOME/.gcenv}"
GCENV_PROFILES_DIR="$GCENV_HOME/profiles"
GCENV_ADC_DIR="$GCENV_HOME/adc"

_gcenv_ensure_dirs() {
  mkdir -p "$GCENV_PROFILES_DIR" "$GCENV_ADC_DIR"
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
  login <name>     Re-run auth for a profile
  edit <name>      Edit profile settings
  help             Show this help message

Options for 'add':
  --account=EMAIL    GCP account email
  --project=ID       GCP project ID

Examples:
  gcenv add prod --account=me@company.com --project=my-project
  gcenv use prod
  gcenv list
EOF
}

_gcenv_profile_path() {
  echo "$GCENV_PROFILES_DIR/$1.env"
}

_gcenv_profile_exists() {
  [[ -f "$(_gcenv_profile_path "$1")" ]]
}

_gcenv_read_profile() {
  local profile_file
  profile_file="$(_gcenv_profile_path "$1")"
  if [[ ! -f "$profile_file" ]]; then
    echo "gcenv: profile '$1' not found" >&2
    return 1
  fi
  source "$profile_file"
}

_gcenv_add() {
  local name="" account="" project=""

  # Parse arguments
  for arg in "$@"; do
    case "$arg" in
      --account=*) account="${arg#--account=}" ;;
      --project=*) project="${arg#--project=}" ;;
      -*) echo "gcenv: unknown option '$arg'" >&2; return 1 ;;
      *) [[ -z "$name" ]] && name="$arg" ;;
    esac
  done

  if [[ -z "$name" ]]; then
    echo -n "Profile name: "
    read -r name
  fi

  if [[ -z "$name" ]]; then
    echo "gcenv: profile name is required" >&2
    return 1
  fi

  if _gcenv_profile_exists "$name"; then
    echo "gcenv: profile '$name' already exists. Use 'gcenv edit $name' to modify." >&2
    return 1
  fi

  if [[ -z "$account" ]]; then
    echo -n "GCP account email: "
    read -r account
  fi

  if [[ -z "$project" ]]; then
    echo -n "GCP project ID: "
    read -r project
  fi

  if [[ -z "$account" || -z "$project" ]]; then
    echo "gcenv: account and project are required" >&2
    return 1
  fi

  _gcenv_ensure_dirs

  cat > "$(_gcenv_profile_path "$name")" <<EOF
GCENV_ACCOUNT=$account
GCENV_PROJECT=$project
EOF

  echo "Profile '$name' created."
  echo "  Account: $account"
  echo "  Project: $project"
  echo ""

  echo -n "Authenticate now? (y/N) "
  read -r answer
  if [[ "$answer" =~ ^[Yy] ]]; then
    _gcenv_login "$name"
  else
    echo "Run 'gcenv login $name' later to authenticate."
  fi
}

_gcenv_use() {
  local name="$1"

  if [[ -z "$name" ]]; then
    echo "Usage: gcenv use <profile-name>" >&2
    return 1
  fi

  local GCENV_ACCOUNT GCENV_PROJECT
  _gcenv_read_profile "$name" || return 1

  export CLOUDSDK_CORE_ACCOUNT="$GCENV_ACCOUNT"
  export CLOUDSDK_CORE_PROJECT="$GCENV_PROJECT"
  export CLOUDSDK_BILLING_QUOTA_PROJECT="$GCENV_PROJECT"
  export GCENV_ACTIVE="$name"

  local adc_file="$GCENV_ADC_DIR/$name.json"
  if [[ -f "$adc_file" ]]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$adc_file"
  else
    unset GOOGLE_APPLICATION_CREDENTIALS
    echo "gcenv: warning: no ADC credentials for '$name'. Run 'gcenv login $name' to authenticate." >&2
  fi

  echo "Switched to '$name'"
  echo "  Account: $GCENV_ACCOUNT"
  echo "  Project: $GCENV_PROJECT"
}

_gcenv_list() {
  _gcenv_ensure_dirs

  local profiles=("$GCENV_PROFILES_DIR"/*.env)

  if [[ ! -f "${profiles[0]}" ]]; then
    echo "No profiles found. Run 'gcenv add <name>' to create one."
    return 0
  fi

  local name
  for f in "${profiles[@]}"; do
    name="$(basename "$f" .env)"
    if [[ "$name" == "$GCENV_ACTIVE" ]]; then
      echo "* $name (active)"
    else
      echo "  $name"
    fi
  done
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

  local GCENV_ACCOUNT GCENV_PROJECT
  _gcenv_read_profile "$name" || return 1

  echo "Authenticating profile '$name' ($GCENV_ACCOUNT)..."
  echo ""

  echo "==> Step 1/3: gcloud auth login"
  if ! gcloud auth login "$GCENV_ACCOUNT"; then
    echo "gcenv: auth login failed" >&2
    return 1
  fi

  echo ""
  echo "==> Step 2/3: Application Default Credentials login"
  if ! gcloud auth application-default login; then
    echo "gcenv: ADC login failed" >&2
    return 1
  fi

  # Copy ADC to profile-specific location
  local default_adc="$HOME/.config/gcloud/application_default_credentials.json"
  if [[ -f "$default_adc" ]]; then
    cp "$default_adc" "$GCENV_ADC_DIR/$name.json"
  fi

  echo ""
  echo "==> Step 3/3: Setting quota project"
  if ! gcloud auth application-default set-quota-project "$GCENV_PROJECT"; then
    echo "gcenv: set-quota-project failed" >&2
    return 1
  fi

  # Re-copy ADC after quota project is set
  if [[ -f "$default_adc" ]]; then
    cp "$default_adc" "$GCENV_ADC_DIR/$name.json"
  fi

  echo ""
  echo "Authentication complete for '$name'."
  echo "Run 'gcenv use $name' to activate this profile."
}

_gcenv_edit() {
  local name="$1"

  if [[ -z "$name" ]]; then
    echo "Usage: gcenv edit <profile-name>" >&2
    return 1
  fi

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

gcenv() {
  local command="${1:-help}"
  shift 2>/dev/null

  case "$command" in
    add)     _gcenv_add "$@" ;;
    use)     _gcenv_use "$@" ;;
    list|ls) _gcenv_list ;;
    current) _gcenv_current ;;
    remove|rm) _gcenv_remove "$@" ;;
    login)   _gcenv_login "$@" ;;
    edit)    _gcenv_edit "$@" ;;
    help|--help|-h) _gcenv_help ;;
    *)
      echo "gcenv: unknown command '$command'" >&2
      _gcenv_help
      return 1
      ;;
  esac
}

#compdef gcenv

_gcenv() {
  local -a commands claude_subs profiles
  local gcenv_dir="${GCENV_HOME:-$HOME/.gcenv}/profiles"

  commands=(
    'add:Create a new gcloud profile'
    'use:Switch current terminal to a profile'
    'list:List all profiles'
    'current:Show active profile details'
    'remove:Delete a profile'
    'login:Re-run auth for a profile'
    'reauth:Refresh user-account auth only'
    'edit:Edit profile settings'
    'claude:Claude Code integration'
    'help:Show help message'
  )

  claude_subs=(
    'use:Set the active profile for this Claude session'
    'show:Show the active profile'
    'off:Clear the active profile'
    'run:Run a single command with profile env'
    'init:Install Claude Code hook'
  )

  if (( CURRENT == 2 )); then
    _describe -t commands 'gcenv command' commands
    return
  fi

  if [[ "${words[2]}" == "claude" ]]; then
    if (( CURRENT == 3 )); then
      _describe -t subcommands 'claude subcommand' claude_subs
      return
    fi
    if (( CURRENT == 4 )) && [[ "${words[3]}" == "use" ]] && [[ -d "$gcenv_dir" ]]; then
      profiles=(${gcenv_dir}/*.env(N:t:r))
      _describe -t profiles 'profile' profiles
      return
    fi
    return
  fi

  case "${words[2]}" in
    use|remove|rm|login|reauth|edit)
      if [[ -d "$gcenv_dir" ]]; then
        profiles=(${gcenv_dir}/*.env(N:t:r))
        _describe -t profiles 'profile' profiles
      fi
      ;;
  esac
}

_gcenv "$@"

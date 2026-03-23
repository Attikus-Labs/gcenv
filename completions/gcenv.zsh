#compdef gcenv

_gcenv() {
  local -a commands profiles

  commands=(
    'add:Create a new gcloud profile'
    'use:Switch current terminal to a profile'
    'list:List all profiles'
    'current:Show active profile details'
    'remove:Delete a profile'
    'login:Re-run auth for a profile'
    'edit:Edit profile settings'
    'help:Show help message'
  )

  if (( CURRENT == 2 )); then
    _describe -t commands 'gcenv command' commands
    return
  fi

  case "${words[2]}" in
    use|remove|rm|login|edit)
      local gcenv_dir="${GCENV_HOME:-$HOME/.gcenv}/profiles"
      if [[ -d "$gcenv_dir" ]]; then
        profiles=(${gcenv_dir}/*.env(N:t:r))
        _describe -t profiles 'profile' profiles
      fi
      ;;
  esac
}

_gcenv "$@"

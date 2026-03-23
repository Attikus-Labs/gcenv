#!/usr/bin/env bash
# Bash completion for gcenv

_gcenv_completions() {
  local cur prev commands
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  commands="add use list current remove login edit help"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    return
  fi

  case "$prev" in
    use|remove|rm|login|edit)
      local gcenv_dir="${GCENV_HOME:-$HOME/.gcenv}/profiles"
      if [[ -d "$gcenv_dir" ]]; then
        local profiles
        profiles=$(ls "$gcenv_dir"/*.env 2>/dev/null | xargs -I{} basename {} .env)
        COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
      fi
      ;;
  esac
}

complete -F _gcenv_completions gcenv

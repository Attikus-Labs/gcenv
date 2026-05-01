#!/usr/bin/env bash
# Bash completion for gcenv

_gcenv_completions() {
  local cur prev commands claude_subs gcenv_dir profiles
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  commands="add use list current remove login reauth edit claude help"
  claude_subs="use show off run init"
  gcenv_dir="${GCENV_HOME:-$HOME/.gcenv}/profiles"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    return
  fi

  # gcenv claude <subcmd> [profile?]
  if [[ "${COMP_WORDS[1]}" == "claude" ]]; then
    if [[ ${COMP_CWORD} -eq 2 ]]; then
      COMPREPLY=($(compgen -W "$claude_subs" -- "$cur"))
      return
    fi
    if [[ ${COMP_CWORD} -eq 3 && "${COMP_WORDS[2]}" == "use" && -d "$gcenv_dir" ]]; then
      profiles=$(ls "$gcenv_dir"/*.env 2>/dev/null | xargs -I{} basename {} .env)
      COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
      return
    fi
    return
  fi

  case "$prev" in
    use|remove|rm|login|reauth|edit)
      if [[ -d "$gcenv_dir" ]]; then
        profiles=$(ls "$gcenv_dir"/*.env 2>/dev/null | xargs -I{} basename {} .env)
        COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
      fi
      ;;
  esac
}

complete -F _gcenv_completions gcenv

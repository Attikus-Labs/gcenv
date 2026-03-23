#!/usr/bin/env zsh
# gcenv — oh-my-zsh plugin
# Provides gcenv shell function and prompt integration.

# Source the core gcenv functions
source "${0:A:h}/gcenv.sh"

# Load zsh completions
fpath=("${0:A:h}/completions" $fpath)
autoload -Uz compinit && compinit -C

# Prompt helper — add $(gcenv_prompt_info) to your PROMPT or RPROMPT
# Customizable via ZSH_THEME_GCENV_PREFIX and ZSH_THEME_GCENV_SUFFIX
gcenv_prompt_info() {
  [[ -n "$GCENV_ACTIVE" ]] || return
  echo "${ZSH_THEME_GCENV_PREFIX:=%{$fg[blue]%}☁ }${GCENV_ACTIVE}${ZSH_THEME_GCENV_SUFFIX:=%{$reset_color%}}"
}

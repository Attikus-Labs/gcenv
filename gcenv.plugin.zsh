#!/usr/bin/env zsh
# gcenv — oh-my-zsh plugin
# Provides gcenv shell function and prompt integration.

# Source the core gcenv functions (lives inside the Claude plugin so the same
# file works both as a sourced shell function and inside the installed plugin).
# Path contract: install.sh symlinks the *repo root* (not plugins/gcenv/) as
# the omz plugin directory, so ${0:A:h} resolves to the repo root. Don't move
# this file into plugins/gcenv/ without also updating that symlink.
source "${0:A:h}/plugins/gcenv/gcenv.sh"

# Load zsh completions
fpath=("${0:A:h}/completions" $fpath)
autoload -Uz compinit && compinit -C

# Prompt helper — add $(gcenv_prompt_info) to your PROMPT or RPROMPT
# Customizable via ZSH_THEME_GCENV_PREFIX and ZSH_THEME_GCENV_SUFFIX
gcenv_prompt_info() {
  [[ -n "$GCENV_ACTIVE" ]] || return
  echo "${ZSH_THEME_GCENV_PREFIX:=%{$fg[blue]%}☁ }${GCENV_ACTIVE}${ZSH_THEME_GCENV_SUFFIX:=%{$reset_color%}}"
}

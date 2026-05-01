#!/usr/bin/env bash
# gcenv installer
#
# Two ways to run:
#   1. From a clone:  ./install.sh        (this script lives in the repo)
#   2. Direct:        curl -fsSL https://raw.githubusercontent.com/Attikus-Labs/gcenv/main/install.sh | bash
#
# In curl|bash mode, the script clones the repo to ~/.gcenv-src and re-execs
# itself from there so all relative paths resolve.

set -euo pipefail

GCENV_REPO_URL="${GCENV_REPO_URL:-https://github.com/Attikus-Labs/gcenv.git}"
GCENV_INSTALL_DIR="${GCENV_INSTALL_DIR:-$HOME/.gcenv-src}"

# Resolve our checkout. ${BASH_SOURCE[0]} is the script path when sourced or
# executed from a file; empty when piped from curl. Even if it's set, the
# "checkout" might not actually contain the gcenv tree (e.g. /tmp scratch).
_gcenv_resolved_repo_dir() {
  local src="${BASH_SOURCE[0]:-}"
  [[ -z "$src" ]] && return 1
  local dir
  dir="$(cd "$(dirname "$src")" 2>/dev/null && pwd)" || return 1
  [[ -f "$dir/plugins/gcenv/gcenv.sh" ]] || return 1
  echo "$dir"
}

if ! GCENV_REPO_DIR="$(_gcenv_resolved_repo_dir)"; then
  # curl|bash mode: clone (or update) the repo and re-exec install.sh from it.
  if ! command -v git >/dev/null 2>&1; then
    echo "gcenv: git is required to install. Install git, then re-run." >&2
    exit 1
  fi
  if [[ -d "$GCENV_INSTALL_DIR/.git" ]]; then
    echo "Updating existing gcenv checkout at $GCENV_INSTALL_DIR..."
    git -C "$GCENV_INSTALL_DIR" pull --quiet --ff-only || {
      echo "gcenv: 'git pull' failed in $GCENV_INSTALL_DIR; resolve manually and re-run." >&2
      exit 1
    }
  else
    echo "Cloning gcenv to $GCENV_INSTALL_DIR..."
    git clone --quiet "$GCENV_REPO_URL" "$GCENV_INSTALL_DIR" || {
      echo "gcenv: failed to clone $GCENV_REPO_URL" >&2
      exit 1
    }
  fi
  exec bash "$GCENV_INSTALL_DIR/install.sh" "$@"
fi

GCENV_HOME="${HOME}/.gcenv"

echo "Installing gcenv from $GCENV_REPO_DIR..."
echo ""

# Create data directories
mkdir -p "$GCENV_HOME/profiles" "$GCENV_HOME/adc"
echo "Created $GCENV_HOME/"

# Detect shell
detect_shell() {
  local shell_name
  shell_name="$(basename "${SHELL:-/bin/bash}")"
  echo "$shell_name"
}

CURRENT_SHELL="$(detect_shell)"

# Check for oh-my-zsh
has_omz() {
  [[ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins" ]]
}

install_omz_plugin() {
  local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/gcenv"
  local zshrc="$HOME/.zshrc"

  if [[ -L "$plugin_dir" || -d "$plugin_dir" ]]; then
    rm -rf "$plugin_dir"
  fi

  ln -s "$GCENV_REPO_DIR" "$plugin_dir"
  echo "Symlinked oh-my-zsh plugin: $plugin_dir -> $GCENV_REPO_DIR"

  # Auto-add gcenv to plugins list in .zshrc
  if grep -qE '^plugins=\(.*gcenv.*\)' "$zshrc" 2>/dev/null; then
    echo "gcenv already in plugins list"
  elif grep -qE '^plugins=\(' "$zshrc" 2>/dev/null; then
    # Append gcenv to existing plugins=(...)
    sed -i '' 's/^plugins=(\(.*\))/plugins=(\1 gcenv)/' "$zshrc"
    echo "Added gcenv to plugins list in $zshrc"
  else
    echo "Could not find plugins=(...) in $zshrc. Please add 'gcenv' manually:"
    echo "  plugins=(... gcenv)"
  fi

  echo ""
}

# Detect and configure Powerlevel10k prompt segment
has_p10k() {
  [[ -f "$HOME/.p10k.zsh" ]]
}

install_p10k_segment() {
  local p10k="$HOME/.p10k.zsh"

  # Check if gcenv segment already exists
  if grep -qF 'prompt_gcenv' "$p10k" 2>/dev/null; then
    echo "p10k gcenv segment already configured"
    return
  fi

  # Add gcenv to POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS (after pyenv if present, otherwise at end)
  if grep -qE '^\s*gcenv\s' "$p10k" 2>/dev/null; then
    : # already in the list
  elif grep -qE '^\s*pyenv\s' "$p10k" 2>/dev/null; then
    sed -i '' '/^[[:space:]]*pyenv[[:space:]]/a\
    gcenv                   # gcloud environment (gcenv)
' "$p10k"
    echo "Added gcenv to p10k right prompt (after pyenv)"
  elif grep -qE 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS' "$p10k" 2>/dev/null; then
    sed -i '' '/POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS/a\
    gcenv                   # gcloud environment (gcenv)
' "$p10k"
    echo "Added gcenv to p10k right prompt"
  fi

  # Add the custom segment function before the example segment
  local segment_code
  segment_code=$(cat <<'SEGMENT'

  # gcenv: show active gcloud profile in prompt
  function prompt_gcenv() {
    [[ -n "$GCENV_ACTIVE" ]] || return
    p10k segment -f 33 -i '☁️' -t "$GCENV_ACTIVE"
  }

  function instant_prompt_gcenv() {
    prompt_gcenv
  }

  typeset -g POWERLEVEL9K_GCENV_FOREGROUND=33
  typeset -g POWERLEVEL9K_GCENV_VISUAL_IDENTIFIER_EXPANSION='☁️'
SEGMENT
)

  # Insert before the example segment block
  if grep -qF 'function prompt_example()' "$p10k" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    awk -v seg="$segment_code" '
      /# Example of a user-defined prompt segment/ { print seg; print "" }
      { print }
    ' "$p10k" > "$tmp" && mv "$tmp" "$p10k"
  else
    # No example segment found — append before the closing brace
    local tmp
    tmp=$(mktemp)
    awk -v seg="$segment_code" '
      /^}/ && !done { print seg; print ""; done=1 }
      { print }
    ' "$p10k" > "$tmp" && mv "$tmp" "$p10k"
  fi

  echo "Added gcenv prompt segment to $p10k"
}

# Fallback: add RPROMPT for users without p10k
install_rprompt() {
  local zshrc="$HOME/.zshrc"
  if grep -qF 'gcenv_prompt_info' "$zshrc" 2>/dev/null; then
    echo "RPROMPT gcenv_prompt_info already configured"
    return
  fi
  echo "" >> "$zshrc"
  echo "# gcenv prompt (shows active gcloud profile)" >> "$zshrc"
  echo "RPROMPT='\$(gcenv_prompt_info)'" >> "$zshrc"
  echo "Added RPROMPT with gcenv_prompt_info to $zshrc"
}

install_shell_source() {
  local rc_file

  case "$CURRENT_SHELL" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash)
      if [[ -f "$HOME/.bash_profile" ]]; then
        rc_file="$HOME/.bash_profile"
      else
        rc_file="$HOME/.bashrc"
      fi
      ;;
    *)
      echo "Unsupported shell: $CURRENT_SHELL"
      echo "Manually add to your shell config:"
      echo "  source $GCENV_REPO_DIR/plugins/gcenv/gcenv.sh"
      return
      ;;
  esac

  local source_line="source \"$GCENV_REPO_DIR/plugins/gcenv/gcenv.sh\""

  if grep -qF "gcenv.sh" "$rc_file" 2>/dev/null; then
    echo "gcenv already sourced in $rc_file"
  else
    echo "" >> "$rc_file"
    echo "# gcenv — gcloud environment switcher" >> "$rc_file"
    echo "$source_line" >> "$rc_file"
    echo "Added to $rc_file"
  fi

  # Add bash completions
  if [[ "$CURRENT_SHELL" == "bash" ]]; then
    local comp_line="source \"$GCENV_REPO_DIR/completions/gcenv.bash\""
    if ! grep -qF "gcenv.bash" "$rc_file" 2>/dev/null; then
      echo "$comp_line" >> "$rc_file"
      echo "Added bash completions to $rc_file"
    fi
  fi
}

# Install based on detected setup
if [[ "$CURRENT_SHELL" == "zsh" ]] && has_omz; then
  echo "Detected: zsh with oh-my-zsh"
  install_omz_plugin
else
  echo "Detected: $CURRENT_SHELL"
  install_shell_source
fi

# Install prompt integration
if has_p10k; then
  echo "Detected: Powerlevel10k"
  install_p10k_segment
elif [[ "$CURRENT_SHELL" == "zsh" ]]; then
  install_rprompt
fi

# Optional: install as a Claude Code plugin (self-hosted, this repo).
# The repo is its own marketplace via .claude-plugin/marketplace.json.
install_claude_plugin() {
  if ! command -v claude >/dev/null 2>&1; then
    return 0
  fi

  echo ""
  echo "Detected Claude Code on PATH."
  echo -n "Also install gcenv as a Claude Code plugin? (y/N) "
  read -r answer
  if [[ ! "$answer" =~ ^[Yy] ]]; then
    return 0
  fi

  # Prefer the GitHub origin so /plugin update works against the canonical
  # repo. Fall back to the local absolute path during dev / pre-publish.
  local marketplace_source=""
  if command -v git >/dev/null 2>&1 && git -C "$GCENV_REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local origin_url
    origin_url="$(git -C "$GCENV_REPO_DIR" config --get remote.origin.url 2>/dev/null || true)"
    case "$origin_url" in
      git@github.com:*)
        marketplace_source="${origin_url#git@github.com:}"
        marketplace_source="${marketplace_source%.git}"
        ;;
      https://github.com/*)
        marketplace_source="${origin_url#https://github.com/}"
        marketplace_source="${marketplace_source%.git}"
        ;;
    esac
  fi
  if [[ -z "$marketplace_source" ]]; then
    marketplace_source="$GCENV_REPO_DIR"
    echo "  (using local repo path; once this is on GitHub, re-run for the canonical install)"
  fi

  echo "  Adding marketplace: $marketplace_source"
  if ! claude /plugin marketplace add "$marketplace_source"; then
    echo "gcenv: 'claude /plugin marketplace add' failed." >&2
    echo "  Try manually:" >&2
    echo "    claude /plugin marketplace add $marketplace_source" >&2
    echo "    claude /plugin install gcenv@gcenv" >&2
    return 0
  fi

  echo "  Installing plugin: gcenv@gcenv"
  if ! claude /plugin install gcenv@gcenv; then
    echo "gcenv: 'claude /plugin install' failed." >&2
    echo "  Try manually:  claude /plugin install gcenv@gcenv" >&2
    return 0
  fi

  echo "Claude Code plugin installed."
}

install_claude_plugin

echo ""
echo "Installation complete!"
echo ""
echo "Restart your terminal or run:"
echo "  source ~/.${CURRENT_SHELL}rc"
echo ""
echo "Then get started:"
echo "  gcenv add <profile-name>"
echo "  gcenv login <profile-name>"
echo "  gcenv use <profile-name>"

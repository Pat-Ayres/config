# Brew completions — must be before compinit
if type brew &>/dev/null; then
  FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
fi

# Completions
autoload -Uz compinit && compinit

# History
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS SHARE_HISTORY HIST_VERIFY

# Shell options
setopt AUTO_CD COMPLETE_IN_WORD ALWAYS_TO_END

# Key bindings: vim mode with useful Ctrl shortcuts preserved
bindkey -v
export KEYTIMEOUT=1    # 10ms Esc timeout (default is 400ms — sluggish)
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^K' kill-line
bindkey '^W' backward-kill-word
bindkey '^L' clear-screen

# Colored man pages (replaces colored-man-pages plugin)
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'
export LESS_TERMCAP_ue=$'\e[0m'

# take function (mkdir + cd)
take() { mkdir -p "$1" && cd "$1" }

# Aliases
source ~/.zshaliases

# Terraform completions
complete -o nospace -C terraform terraform 2>/dev/null || true

eval "$(starship init zsh)"

# chruby - load from system on Linux, brew on macOS
if [[ "$(uname)" == "Darwin" ]] && [[ -f "$(brew --prefix)/opt/chruby/share/chruby/chruby.sh" ]]; then
  source "$(brew --prefix)/opt/chruby/share/chruby/chruby.sh"
  source "$(brew --prefix)/opt/chruby/share/chruby/auto.sh"
elif [[ -f /usr/share/chruby/chruby.sh ]]; then
  source /usr/share/chruby/chruby.sh
  source /usr/share/chruby/auto.sh
fi

# make gnu-sed the default sed
PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"
PATH="~/.rd/bin:$PATH"
PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# GO Stuff
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
export GOBIN=$GOPATH/bin
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

eval "$(atuin init zsh)"

if [[ -f ${PANORAMA_TOP}/school-supplies/bin/shell_includes.sh ]]; then
  source ${PANORAMA_TOP}/school-supplies/bin/shell_includes.sh
fi

if [[ $CODESPACES == "true" ]]; then
  # For some reason codespaces has $SHELL set to bash even though my default shell is set to zsh, and the active shell is zsh.
  # This breaks a bunch of stuff, and I don't know why it is happening. A workaround seems to be to force update the shell env var.
  # Using `readlink` here sets the shell to the absolute path of the currently running shell, so that things relying on $SHELL work
  # correctly again.
  export SHELL="$(readlink /proc/$$/exe)"

  # Some repos have an additional rcfile set up for dev tooling in codespaces. Source it if it exists.
  if [[ -f $HOME/.panoramarc ]]; then
    source $HOME/.panoramarc
  fi
fi

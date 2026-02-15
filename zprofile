if [[ "$(uname)" == "Linux" ]]; then
  [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
else
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

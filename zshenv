# Don't overwrite PANORAMA_TOP if in codespace
if [[ $CODESPACES != "true" ]]; then
  # used by panorama dev env
  export PANORAMA_TOP=~/src/panorama
fi

# use docker buildkit for caching etc
export DOCKER_BUILDKIT=1

# sticky title for tmuxp sessions
export DISABLE_AUTO_TILE='true'

# source cargo env for rust stuffs
. "$HOME/.cargo/env"

### PATH STUFF ###

# put vscode in path for cli to work
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# prefer local bin
export PATH="$HOME/.local/bin:$PATH"

# DEPRECATED: LEGACY SUPPORT ONLY
# add personal scripts to path
export PATH="$PATH:/Users/payres/bin"

# add krew to path
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

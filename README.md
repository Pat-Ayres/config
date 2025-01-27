# Dotfiles and Config for Dev Env Setup

This was originally intended to bootstrap use of codespaces, but it became
sufficiently annoying to maintain a separate bootstrapping process just for
codespaces, so I tweaked it to work across platforms (I think...).

## Neovim Config

I have my neovim config stored in a separate repository so I can develop it in
isolation. I do this by cloning that repo to `$HOME/.config/nvimdev` on my
workstation, which allows me to iterate on the config using `NVIM_APPNAME=nvimdev`
without affecting my "stable" ide for other repos. I struggled with getting codespaces
to work properly with this for a while, eventually landing on http cloning it into the
default directory for "stable" use.

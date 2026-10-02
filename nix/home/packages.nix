{ pkgs, lib, ... }:
let
  common = with pkgs; [
    # shell / prompt
    zsh
    starship
    tmux
    atuin

    # editors / vcs
    neovim # built nightly via the neovim-nightly-overlay input in flake.nix
    tree-sitter # CLI; nvim-treesitter (main branch) needs it to build parsers
    git
    git-lfs
    gh
    jujutsu # jj
    lazygit
    delta # aka "git-delta"
    gnupg

    rustup
    bottom

    # CLI ergonomics
    ripgrep
    fd
    fzf
    bat
    eza
    jq
    yq
    tree
    htop
    tokei
    shellcheck
    vhs
    websocat
    zk
    goreleaser
    gnuplot

    # containers / k8s — colima replaces Docker Desktop, matching current setup
    colima
    docker-client
    docker-buildx
    docker-compose
    kubectl
    kubernetes-helm
    kubectx
    kind
    # minikube bundles its own copy of `kubectl` in its output, which
    # collides with the standalone `kubectl` above when home-manager builds
    # the unified profile. lowPrio makes the
    # explicit `kubectl` package win for that shared path.
    (lib.lowPrio minikube)
    k9s
    fluxcd
    kustomize
    kyverno
    kube-linter
    kubeconform
    argo-workflows
    sops
    cosign
    hadolint
    prometheus
    rbspy

    # go toolchain + go-installed tools (~/go/bin in the inventory)
    go
    gopls
    delve
    gotools
    golangci-lint
    go-tools
    govulncheck
    ginkgo
    actionlint
    go-licenses
    helm-docs
    kubernetes-controller-tools
    go-containerregistry
    tflint
    oras
    pkgsite
    setup-envtest
    hugo
    glow

    nodejs_22
    pyright
    typescript
    typescript-language-server
    yaml-language-server

    pyenv
    uv

    chruby

    # cloud
    awscli2
    ssm-session-manager-plugin
  ];

  darwinOnly = with pkgs; [
    # macOS ships BSD coreutils/sed/find; these give the GNU versions.
    coreutils
    findutils
    gnused
    gnugrep
  ];

  linuxOnly = with pkgs; [];
in
{
  home.packages = common
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin darwinOnly
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux linuxOnly;

  # Lets any nix-built macOS GUI apps show up as real .app bundles in
  # ~/Applications — Spotlight/Dock visible, not just a bare binary on PATH.
  targets.darwin.linkApps.enable = false;
  targets.darwin.copyApps.enable = pkgs.stdenv.hostPlatform.isDarwin;
}

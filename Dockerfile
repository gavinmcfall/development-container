# syntax=docker/dockerfile:1
# Devpod image — Gavin's Claude Code dev environment, Ubuntu 24.04.
# Thin driver over declarative config/: each install TYPE is one YAML file
# (apt, apt-repos, binaries, scripts, npm, languages) consumed by install/*.sh,
# so adding/removing a tool = edit one YAML and rebuild. Package choices are
# evidence-driven — see inventory/tool-usage-report.md. Personal data + dotfiles
# live on the PVC, NOT the image (see devpod-design.md). Build in CI -> zot.
FROM ubuntu:24.04

ARG USERNAME=gavin
ARG UID=1000
ARG GID=1000
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Pacific/Auckland \
    LANG=en_US.UTF-8

# ---- bootstrap: minimal fetch tools + yq (needed to read the config YAMLs) --
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg \
    && arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq \
    && rm -rf /var/lib/apt/lists/*

# ---- config + install drivers ----------------------------------------------
COPY config  /opt/devpod/config
COPY install /opt/devpod/install

# ---- system packages, third-party repos, binaries, install-script tools -----
RUN sh /opt/devpod/install/apt.sh \
    && sh /opt/devpod/install/apt-repos.sh \
    && sh /opt/devpod/install/binaries.sh \
    && sh /opt/devpod/install/scripts.sh

# ---- system post-config: Ubuntu-renamed binaries + rootless-podman defaults --
# fd-find/bat install as fdfind/batcat on Ubuntu; expose the conventional names.
# /etc/containers/* are SYSTEM paths (NOT shadowed by the home PVC at runtime):
#   storage=vfs    -> rootless podman works with NO /dev/fuse in an unprivileged
#                     pod (overlay+fuse-overlayfs can be enabled later if the
#                     cluster ever provisions /dev/fuse).
#   cgroupfs+file  -> no systemd/journald in the pod, so don't use them.
RUN set -eux; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    ln -sf /usr/bin/batcat /usr/local/bin/bat; \
    mkdir -p /etc/containers; \
    printf '[storage]\ndriver = "vfs"\n' > /etc/containers/storage.conf; \
    printf '[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' > /etc/containers/containers.conf

# ---- Go (system-wide; version from config/languages.yaml) -------------------
RUN set -eux; arch="$(dpkg --print-architecture)"; \
    gov="$(yq '.go' /opt/devpod/config/languages.yaml)"; \
    curl -fsSL "https://go.dev/dl/go${gov}.linux-${arch}.tar.gz" | tar -C /usr/local -xz
ENV PATH=/usr/local/go/bin:$PATH

# ---- user (uid/gid match WSL2 so /home/gavin paths + PVC ownership work) -----
# ubuntu:24.04 ships a default 'ubuntu' user at uid/gid 1000 — remove it first.
RUN userdel --remove ubuntu 2>/dev/null || true; \
    groupdel ubuntu 2>/dev/null || true; \
    groupadd -g ${GID} ${USERNAME} \
    && useradd -m -u ${UID} -g ${GID} -s /usr/bin/zsh ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && echo "${USERNAME}:100000:65536" > /etc/subuid \
    && echo "${USERNAME}:100000:65536" > /etc/subgid
USER ${USERNAME}
WORKDIR /home/${USERNAME}
ENV HOME=/home/${USERNAME}

# nvm/oh-my-zsh need bash — sourcing nvm.sh under dash with `set -u` fails.
SHELL ["/bin/bash", "-c"]

# ---- per-user toolchains (nvm/node, rust, uv, oh-my-zsh, claude, npm globals)
# Installs into $HOME; on the real pod $HOME is the PVC, so this is a bootstrap —
# the PVC seed (rsync + chezmoi apply) is the source of truth at runtime.
RUN set -ex; \
    nodev="$(yq '.node' /opt/devpod/config/languages.yaml)"; \
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash; \
    export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; \
    nvm install "$nodev"; nvm alias default "$nodev"; \
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path; \
    curl -fsSL https://astral.sh/uv/install.sh | sh; \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; \
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"; \
    curl -fsSL https://claude.ai/install.sh | bash || true; \
    sh /opt/devpod/install/npm.sh

ENV PATH=/home/${USERNAME}/.local/bin:/home/${USERNAME}/.cargo/bin:$PATH

# ---- OPTIONAL: full Homebrew parity (inventory/Brewfile) --------------------
# linuxbrew works in-container but is heavy; the binaries.yaml/scripts.yaml tools
# already cover the used set. Enable only if you want all 126 formulae:
#   RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#   COPY inventory/Brewfile /tmp/Brewfile && brew bundle --file=/tmp/Brewfile
# rootless podman: added in a later iteration once base image is validated.

SHELL ["/usr/bin/zsh", "-c"]
CMD ["/usr/bin/zsh", "-lc", "tmux new -A -s main"]

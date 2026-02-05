#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0" >&2
  exit 1
fi

echo "==> Updating APT and installing base tools"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  jq \
  gnupg \
  apt-transport-https

# Ensure snap is available (normally on Ubuntu it is)
if ! command -v snap >/dev/null 2>&1; then
  apt-get install -y snapd
fi

# Ensure /snap/bin is in PATH for all shells
if ! grep -q "/snap/bin" /etc/environment; then
  echo "==> Adding /snap/bin to PATH"
  sed -i 's#^PATH=\(.*\)$#PATH=\1:/snap/bin#' /etc/environment || true
fi

# Install Helm via snap (classic)
if ! command -v helm >/dev/null 2>&1; then
  echo "==> Installing Helm"
  snap install helm --classic
fi

# Install subctl (latest)
if ! command -v subctl >/dev/null 2>&1; then
  echo "==> Installing subctl (latest)"
  curl -Ls https://get.submariner.io | bash
  # Move to /usr/local/bin if installed in ~/.local/bin
  if [[ -f "/root/.local/bin/subctl" ]]; then
    mv /root/.local/bin/subctl /usr/local/bin/subctl
    chmod +x /usr/local/bin/subctl
  fi
fi

echo "==> Tools installed"
helm version || true
subctl version || true
echo "Note: kubectl will be available after MicroK8s installation (next step)"
#!/usr/bin/env bash
set -euo pipefail

# One-shot bootstrap for native Windows disk deployment (no QEMU runtime).
# Intended to run from DigitalOcean Recovery ISO environment.

REPO_URL="${REPO_URL:-https://github.com/korasu-ho/auto-install-windows-BYKORASU.git}"
REPO_DIR="${REPO_DIR:-/root/auto-install-windows-BYKORASU}"
IMAGE_URL="${IMAGE_URL:-}"
SOURCE_TYPE="${SOURCE_TYPE:-auto}"
TARGET_DISK="${TARGET_DISK:-/dev/vda}"
CONFIRM_DESTROY_DISK="${CONFIRM_DESTROY_DISK:-NO}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Error: run as root (sudo)."
  exit 1
fi

if [[ -z "${IMAGE_URL}" ]]; then
  echo "Error: IMAGE_URL is required."
  echo "Example:"
  echo "  sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://example.com/windows.img.gz' SOURCE_TYPE=gz bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/korasu-ho/auto-install-windows-BYKORASU/main/droplet_native_one_shot_setup.sh)\""
  exit 1
fi

if [[ "${CONFIRM_DESTROY_DISK}" != "YES" ]]; then
  echo "Error: set CONFIRM_DESTROY_DISK=YES to continue."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git

if [[ -d "${REPO_DIR}/.git" ]]; then
  git -C "${REPO_DIR}" pull --ff-only
else
  git clone "${REPO_URL}" "${REPO_DIR}"
fi

cd "${REPO_DIR}"
chmod +x install_windows_native_disk.sh

CONFIRM_DESTROY_DISK="${CONFIRM_DESTROY_DISK}" \
IMAGE_URL="${IMAGE_URL}" \
SOURCE_TYPE="${SOURCE_TYPE}" \
TARGET_DISK="${TARGET_DISK}" \
./install_windows_native_disk.sh

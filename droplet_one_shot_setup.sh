#!/usr/bin/env bash
set -euo pipefail

# One-shot bootstrap for DigitalOcean droplet:
# - install git
# - clone or update this repository
# - execute unattended Windows installer

REPO_URL="${REPO_URL:-https://github.com/korasu-ho/auto-install-windows-BYKORASU.git}"
REPO_DIR="${REPO_DIR:-/root/auto-install-windows-BYKORASU}"
WIN_VERSION_CHOICE="${WIN_VERSION_CHOICE:-3}"
WIN_ADMIN_PASSWORD="${WIN_ADMIN_PASSWORD:-ChangeMe123!}"
ISO_URL="${ISO_URL:-}"
VM_CPUS="${VM_CPUS:-4}"
VM_RAM_MB="${VM_RAM_MB:-6144}"
RDP_HOST_PORT="${RDP_HOST_PORT:-3389}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Error: run as root (sudo)."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git

if [[ -d "${REPO_DIR}/.git" ]]; then
  echo "[INFO] Repository exists, pulling latest changes..."
  git -C "${REPO_DIR}" pull --ff-only
else
  echo "[INFO] Cloning repository..."
  git clone "${REPO_URL}" "${REPO_DIR}"
fi

cd "${REPO_DIR}"
chmod +x install_windows_auto.sh start_windows_vm.sh stop_windows_vm.sh diagnose_rdp.sh

if [[ "${WIN_VERSION_CHOICE}" == "4" ]]; then
  if [[ -z "${ISO_URL}" ]]; then
    echo "Error: WIN_VERSION_CHOICE=4 requires ISO_URL"
    exit 1
  fi
fi

echo "[INFO] Starting unattended installer..."
WIN_VERSION_CHOICE="${WIN_VERSION_CHOICE}" \
WIN_ADMIN_PASSWORD="${WIN_ADMIN_PASSWORD}" \
ISO_URL="${ISO_URL}" \
VM_CPUS="${VM_CPUS}" \
VM_RAM_MB="${VM_RAM_MB}" \
RDP_HOST_PORT="${RDP_HOST_PORT}" \
VNC_DISPLAY="${VNC_DISPLAY}" \
./install_windows_auto.sh

echo

echo "[DONE] Installer started."
echo "VNC  : <droplet-ip>:$((5900 + VNC_DISPLAY))"
echo "RDP  : <droplet-ip>:${RDP_HOST_PORT}"
echo "After install, run: ./stop_windows_vm.sh then ./start_windows_vm.sh"

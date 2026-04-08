#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Error: run as root (sudo)."
  exit 1
fi

VM_NAME="${VM_NAME:-winvm}"
BASE_DIR="${BASE_DIR:-/opt/${VM_NAME}}"
DISK_PATH="${DISK_PATH:-${BASE_DIR}/${VM_NAME}.qcow2}"
VM_CPUS="${VM_CPUS:-4}"
VM_RAM_MB="${VM_RAM_MB:-6144}"
RDP_HOST_PORT="${RDP_HOST_PORT:-3389}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"
QEMU_PIDFILE="${BASE_DIR}/qemu-run.pid"

if [[ ! -f "${DISK_PATH}" ]]; then
  echo "Error: disk not found: ${DISK_PATH}"
  exit 1
fi

if [[ -f "${QEMU_PIDFILE}" ]] && kill -0 "$(cat "${QEMU_PIDFILE}")" 2>/dev/null; then
  echo "Windows VM already running (pid $(cat "${QEMU_PIDFILE}"))."
  exit 0
fi

qemu-system-x86_64 \
  -name "${VM_NAME}" \
  -machine type=q35,accel=kvm:tcg \
  -cpu host \
  -smp "${VM_CPUS}" \
  -m "${VM_RAM_MB}" \
  -drive file="${DISK_PATH}",if=ide,cache=writeback,discard=unmap,format=qcow2 \
  -boot order=c \
  -netdev user,id=net0,hostfwd=tcp::"${RDP_HOST_PORT}"-:3389 \
  -device e1000,netdev=net0 \
  -vnc 0.0.0.0:"${VNC_DISPLAY}" \
  -display none \
  -daemonize \
  -pidfile "${QEMU_PIDFILE}"

echo "Windows VM started"
echo "- RDP: <droplet-ip>:${RDP_HOST_PORT}"
echo "- VNC: <droplet-ip>:$((5900 + VNC_DISPLAY))"

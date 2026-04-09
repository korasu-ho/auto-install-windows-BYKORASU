#!/usr/bin/env bash
set -euo pipefail

# Export Windows disk from QEMU qcow2 into raw image (.img) and compressed (.img.gz).

if [[ ${EUID} -ne 0 ]]; then
  echo "Error: run as root (sudo)."
  exit 1
fi

VM_NAME="${VM_NAME:-winvm}"
BASE_DIR="${BASE_DIR:-/opt/${VM_NAME}}"
DISK_PATH="${DISK_PATH:-${BASE_DIR}/${VM_NAME}.qcow2}"
EXPORT_DIR="${EXPORT_DIR:-${BASE_DIR}/export}"
RAW_NAME="${RAW_NAME:-windows-from-qcow2.img}"
COMPRESS="${COMPRESS:-true}"
STOP_VM_FIRST="${STOP_VM_FIRST:-true}"

RUN_PIDFILE="${BASE_DIR}/qemu-run.pid"
INSTALL_PIDFILE="${BASE_DIR}/qemu-install.pid"
RAW_PATH="${EXPORT_DIR}/${RAW_NAME}"
GZ_PATH="${RAW_PATH}.gz"

stop_pidfile() {
  local pidfile="$1"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" || true
    fi
    rm -f "$pidfile"
  fi
}

if [[ ! -f "${DISK_PATH}" ]]; then
  echo "Error: qcow2 disk not found: ${DISK_PATH}"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y qemu-utils gzip

if [[ "${STOP_VM_FIRST}" == "true" ]]; then
  echo "[INFO] Stopping VM before export..."
  stop_pidfile "${RUN_PIDFILE}"
  stop_pidfile "${INSTALL_PIDFILE}"
  pkill -f qemu-system-x86_64 || true
fi

mkdir -p "${EXPORT_DIR}"

echo "[INFO] Converting qcow2 to raw image..."
qemu-img convert -p -f qcow2 -O raw "${DISK_PATH}" "${RAW_PATH}"

if [[ "${COMPRESS}" == "true" ]]; then
  echo "[INFO] Compressing raw image..."
  gzip -f "${RAW_PATH}"
  echo "[DONE] Export ready: ${GZ_PATH}"
  ls -lh "${GZ_PATH}"
else
  echo "[DONE] Export ready: ${RAW_PATH}"
  ls -lh "${RAW_PATH}"
fi

echo
echo "Next: upload exported image to an external URL, then deploy in Recovery ISO using install_windows_native_disk.sh"

#!/usr/bin/env bash
set -euo pipefail

# Export RAW VirtIO image into compressed .img.gz for native disk deployment.

if [[ ${EUID} -ne 0 ]]; then
  echo "Error: run as root (sudo)."
  exit 1
fi

VM_NAME="${VM_NAME:-winvm}"
BASE_DIR="${BASE_DIR:-/opt/${VM_NAME}}"
RAW_IMG_PATH="${RAW_IMG_PATH:-${BASE_DIR}/${VM_NAME}-do-virtio.img}"
EXPORT_DIR="${EXPORT_DIR:-${BASE_DIR}/export}"
OUTPUT_NAME="${OUTPUT_NAME:-windows-do-compatible.img.gz}"
STOP_BUILDER_FIRST="${STOP_BUILDER_FIRST:-true}"
BUILDER_PIDFILE="${BASE_DIR}/qemu-do-builder.pid"
OUT_PATH="${EXPORT_DIR}/${OUTPUT_NAME}"

mkdir -p "${EXPORT_DIR}"

if [[ ! -f "${RAW_IMG_PATH}" ]]; then
  echo "Error: RAW image not found: ${RAW_IMG_PATH}"
  exit 1
fi

if [[ "${STOP_BUILDER_FIRST}" == "true" ]]; then
  if [[ -f "${BUILDER_PIDFILE}" ]] && kill -0 "$(cat "${BUILDER_PIDFILE}")" 2>/dev/null; then
    kill "$(cat "${BUILDER_PIDFILE}")" || true
    rm -f "${BUILDER_PIDFILE}"
  fi
fi

echo "Compressing RAW image -> ${OUT_PATH}"
gzip -c "${RAW_IMG_PATH}" > "${OUT_PATH}"

ls -lh "${OUT_PATH}"
echo "Done. Upload this file and deploy with install_windows_native_disk.sh"

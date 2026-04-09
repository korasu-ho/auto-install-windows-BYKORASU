#!/usr/bin/env bash
set -euo pipefail

# Native Windows deployment to droplet disk (no nested VM/QEMU runtime).
# Run this from a recovery environment, because target disk will be overwritten.

if [[ ${EUID} -ne 0 ]]; then
  echo "Error: run as root (sudo)."
  exit 1
fi

IMAGE_URL="${IMAGE_URL:-}"
IMAGE_FILE="${IMAGE_FILE:-}"
TARGET_DISK="${TARGET_DISK:-/dev/vda}"
WORK_DIR="${WORK_DIR:-/tmp/windows-native-deploy}"
CONFIRM_DESTROY_DISK="${CONFIRM_DESTROY_DISK:-NO}"
SOURCE_TYPE="${SOURCE_TYPE:-auto}" # auto|raw|gz|xz

if [[ -z "${IMAGE_URL}" && -z "${IMAGE_FILE}" ]]; then
  echo "Error: IMAGE_URL or IMAGE_FILE is required."
  echo "Example:"
  echo "  sudo CONFIRM_DESTROY_DISK=YES IMAGE_URL='https://example.com/windows.img.gz' ./install_windows_native_disk.sh"
  echo "  sudo CONFIRM_DESTROY_DISK=YES IMAGE_FILE='/path/windows.img.gz' ./install_windows_native_disk.sh"
  exit 1
fi

if [[ "${CONFIRM_DESTROY_DISK}" != "YES" ]]; then
  echo "Safety check failed: set CONFIRM_DESTROY_DISK=YES to continue."
  exit 1
fi

if [[ ! -b "${TARGET_DISK}" ]]; then
  echo "Error: TARGET_DISK not found or not a block device: ${TARGET_DISK}"
  exit 1
fi

mkdir -p "${WORK_DIR}"

log() {
  echo "[INFO] $*"
}

is_mega_url() {
  local url="$1"
  [[ "$url" == *"mega.nz/file/"* || "$url" == *"mega.nz/#!"* ]]
}

is_google_drive_url() {
  local url="$1"
  [[ "$url" == *"drive.google.com"* || "$url" == *"docs.google.com"* ]]
}

apt_install_base() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl wget gzip xz-utils ca-certificates
}

detect_source_type() {
  local src="$1"
  if [[ "${SOURCE_TYPE}" != "auto" ]]; then
    echo "${SOURCE_TYPE}"
    return
  fi

  case "${src}" in
    *.img.gz|*.qcow2.gz|*.raw.gz|*.gz)
      echo "gz"
      ;;
    *.img.xz|*.qcow2.xz|*.raw.xz|*.xz)
      echo "xz"
      ;;
    *)
      echo "raw"
      ;;
  esac
}

stream_write_raw() {
  local source_cmd="$1"
  log "Writing image to ${TARGET_DISK} ..."
  # shellcheck disable=SC2091
  eval "${source_cmd}" | dd of="${TARGET_DISK}" bs=16M conv=fsync status=progress
  sync
}

download_mega_to_file() {
  local url="$1"
  local out_file="$2"

  apt-get install -y megatools
  local marker
  marker="$(mktemp)"
  touch "${marker}"

  log "Downloading from Mega..."
  megadl --path "${WORK_DIR}" "${url}"

  local downloaded
  downloaded="$(find "${WORK_DIR}" -maxdepth 1 -type f -newer "${marker}" | head -n 1 || true)"
  rm -f "${marker}"

  if [[ -z "${downloaded}" ]]; then
    echo "Error: Mega download finished but file not found."
    exit 1
  fi

  mv -f "${downloaded}" "${out_file}"
}

download_gdrive_to_file() {
  local url="$1"
  local out_file="$2"

  apt-get install -y python3 python3-venv
  local venv_path="${WORK_DIR}/.gdown-venv"
  if [[ ! -x "${venv_path}/bin/gdown" ]]; then
    python3 -m venv "${venv_path}"
    "${venv_path}/bin/pip" install --upgrade pip >/dev/null
    "${venv_path}/bin/pip" install gdown >/dev/null
  fi

  log "Downloading from Google Drive..."
  "${venv_path}/bin/gdown" --fuzzy "${url}" -O "${out_file}"
}

write_from_local_file() {
  local file_path="$1"
  local stype="$2"

  if [[ ! -s "${file_path}" ]]; then
    echo "Error: Downloaded file is missing/empty: ${file_path}"
    exit 1
  fi

  case "${stype}" in
    gz)
      stream_write_raw "gzip -dc '${file_path}'"
      ;;
    xz)
      stream_write_raw "xz -dc '${file_path}'"
      ;;
    raw)
      stream_write_raw "cat '${file_path}'"
      ;;
    *)
      echo "Error: Unsupported SOURCE_TYPE: ${stype}"
      exit 1
      ;;
  esac
}

write_direct_stream() {
  local url="$1"
  local stype="$2"

  case "${stype}" in
    gz)
      stream_write_raw "wget -O- '${url}' | gzip -dc"
      ;;
    xz)
      stream_write_raw "wget -O- '${url}' | xz -dc"
      ;;
    raw)
      stream_write_raw "wget -O- '${url}'"
      ;;
    *)
      echo "Error: Unsupported SOURCE_TYPE: ${stype}"
      exit 1
      ;;
  esac
}

post_write_checks() {
  log "Collecting disk info..."
  lsblk "${TARGET_DISK}" || true
  fdisk -l "${TARGET_DISK}" || true
}

main() {
  log "WARNING: This will overwrite ${TARGET_DISK}."
  apt_install_base

  local stype
  if [[ -n "${IMAGE_FILE}" ]]; then
    stype="$(detect_source_type "${IMAGE_FILE}")"
  else
    stype="$(detect_source_type "${IMAGE_URL}")"
  fi
  log "Detected source type: ${stype}"

  if [[ -n "${IMAGE_FILE}" ]]; then
    write_from_local_file "${IMAGE_FILE}" "${stype}"
  elif is_mega_url "${IMAGE_URL}"; then
    local mega_file="${WORK_DIR}/windows-image.bin"
    download_mega_to_file "${IMAGE_URL}" "${mega_file}"
    write_from_local_file "${mega_file}" "${stype}"
  elif is_google_drive_url "${IMAGE_URL}"; then
    local gd_file="${WORK_DIR}/windows-image.bin"
    download_gdrive_to_file "${IMAGE_URL}" "${gd_file}"
    write_from_local_file "${gd_file}" "${stype}"
  else
    write_direct_stream "${IMAGE_URL}" "${stype}"
  fi

  post_write_checks

  cat <<MSG

[DONE] Windows image deployed to ${TARGET_DISK}.
Next steps on DigitalOcean:
1) Set Droplet boot option to Hard Drive.
2) Power cycle the Droplet.
3) Ensure Cloud Firewall allows TCP 3389.
4) Connect from local PC via RDP to <droplet-ip>:3389.

Important:
- RDP success depends on your image containing preconfigured Windows network + RDP.
MSG
}

main "$@"

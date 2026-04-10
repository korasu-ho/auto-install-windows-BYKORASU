#!/usr/bin/env bash
set -euo pipefail

# Auto-install Windows on a Linux VM (e.g., DigitalOcean Droplet) using QEMU.
# Note: This runs Windows as a nested VM (emulation/virtualization inside your droplet),
# not as the droplet host OS replacement.

if [[ ${EUID} -ne 0 ]]; then
  echo "Error: run as root (sudo)."
  exit 1
fi

# ----- Config (can be overridden via env vars) -----
VM_NAME="${VM_NAME:-winvm}"
BASE_DIR="${BASE_DIR:-/opt/${VM_NAME}}"
ISO_PATH="${ISO_PATH:-${BASE_DIR}/windows.iso}"
ISO_URL="${ISO_URL:-}"
WIN_VERSION_CHOICE="${WIN_VERSION_CHOICE:-}"
DISK_PATH="${DISK_PATH:-${BASE_DIR}/${VM_NAME}.qcow2}"
DISK_GB="${DISK_GB:-64}"
VM_CPUS="${VM_CPUS:-4}"
VM_RAM_MB="${VM_RAM_MB:-6144}"
VM_MACHINE="${VM_MACHINE:-pc}"
RDP_HOST_PORT="${RDP_HOST_PORT:-3389}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"  # VNC port = 5900 + display
WIN_ADMIN_PASSWORD="${WIN_ADMIN_PASSWORD:-ChangeMe123!}"
TIMEZONE="${TIMEZONE:-SE Asia Standard Time}"
MIN_ISO_FREE_MB="${MIN_ISO_FREE_MB:-6144}"

# Windows unattended account name. Keep Administrator for easiest RDP setup.
WIN_USER="Administrator"
AUTOUNATTEND_XML="${BASE_DIR}/Autounattend.xml"
AUTOUNATTEND_ISO="${BASE_DIR}/autounattend.iso"
QEMU_PIDFILE="${BASE_DIR}/qemu-install.pid"
ISO_SOURCE_MARKER="${BASE_DIR}/.iso_source_url"

mkdir -p "${BASE_DIR}"

show_windows_menu() {
  cat <<'MENU'
Pilih versi Windows (official Microsoft Evaluation ISO):
1) Windows Server 2016
2) Windows Server 2019
3) Windows Server 2022
4) Custom URL (isi ISO_URL manual)
MENU
}

set_iso_from_choice() {
  local choice="$1"
  case "$choice" in
    1)
      ISO_URL="https://go.microsoft.com/fwlink/p/?LinkID=2195174&clcid=0x409&culture=en-us&country=US"
      ISO_PATH="${BASE_DIR}/windows2016.iso"
      ;;
    2)
      ISO_URL="https://go.microsoft.com/fwlink/p/?LinkID=2195167&clcid=0x409&culture=en-us&country=US"
      ISO_PATH="${BASE_DIR}/windows2019.iso"
      ;;
    3)
      ISO_URL="https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
      ISO_PATH="${BASE_DIR}/windows2022.iso"
      ;;
    4)
      if [[ -z "${ISO_URL}" ]]; then
        echo "Choice 4 selected: set ISO_URL manually."
        echo "Example: ISO_URL='https://example.com/windows.iso' ./install_windows_auto.sh"
        exit 1
      fi
      # Avoid reusing generic default path from previous runs.
      if [[ "${ISO_PATH}" == "${BASE_DIR}/windows.iso" ]]; then
        ISO_PATH="${BASE_DIR}/windows_custom.iso"
      fi
      ;;
    *)
      echo "Invalid WIN_VERSION_CHOICE: ${choice}"
      exit 1
      ;;
  esac
}

resolve_iso_source() {
  if [[ -n "${ISO_URL}" ]]; then
    return
  fi

  if [[ -n "${WIN_VERSION_CHOICE}" ]]; then
    set_iso_from_choice "${WIN_VERSION_CHOICE}"
    return
  fi

  if [[ -t 0 ]]; then
    show_windows_menu
    read -r -p "Masukkan pilihan [1-4]: " choice
    set_iso_from_choice "${choice}"
  fi
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    genisoimage \
    python3 \
    python3-venv \
    curl \
    wget
}

is_mega_url() {
  local url="$1"
  [[ "$url" == *"mega.nz/file/"* || "$url" == *"mega.nz/#!"* ]]
}

download_from_mega() {
  local mega_url="$1"
  local iso_dir
  iso_dir="$(dirname "${ISO_PATH}")"

  mkdir -p "${iso_dir}"

  if ! command -v megadl >/dev/null 2>&1; then
    echo "Installing megatools for Mega download..."
    apt-get install -y megatools
  fi

  local marker
  marker="$(mktemp)"
  touch "$marker"

  echo "Downloading ISO from Mega..."
  megadl --path "${iso_dir}" "$mega_url"

  local downloaded
  downloaded="$(find "${iso_dir}" -maxdepth 1 -type f -newer "$marker" | head -n 1 || true)"
  rm -f "$marker"

  if [[ -z "$downloaded" ]]; then
    echo "Error: Mega download completed but file was not found in ${iso_dir}."
    exit 1
  fi

  if [[ "$downloaded" != "${ISO_PATH}" ]]; then
    mv -f "$downloaded" "${ISO_PATH}"
  fi
  echo "Mega ISO saved to ${ISO_PATH}"
}

is_google_drive_url() {
  local url="$1"
  [[ "$url" == *"drive.google.com"* || "$url" == *"docs.google.com"* ]]
}

ensure_gdown() {
  local venv_path="${BASE_DIR}/.gdown-venv"
  if [[ ! -x "${venv_path}/bin/gdown" ]]; then
    echo "Installing gdown (Google Drive downloader)..." >&2
    python3 -m venv "${venv_path}"
    "${venv_path}/bin/pip" install --upgrade pip >/dev/null
    "${venv_path}/bin/pip" install gdown >/dev/null
  fi

  if [[ ! -x "${venv_path}/bin/gdown" ]]; then
    echo "Error: gdown binary is missing after installation: ${venv_path}/bin/gdown"
    exit 1
  fi

  echo "${venv_path}/bin/gdown"
}

download_from_gdrive() {
  local gdrive_url="$1"
  local gdown_bin
  gdown_bin="$(ensure_gdown)"

  echo "Downloading ISO from Google Drive via gdown..."
  "${gdown_bin}" --fuzzy "$gdrive_url" -O "${ISO_PATH}"

  if [[ ! -s "${ISO_PATH}" ]]; then
    echo "Error: gdown finished but ISO file is empty or missing: ${ISO_PATH}"
    exit 1
  fi

  echo "Google Drive ISO saved to ${ISO_PATH}"
}

check_iso_target_free_space() {
  local iso_dir
  iso_dir="$(dirname "${ISO_PATH}")"
  mkdir -p "${iso_dir}"

  local avail_mb
  avail_mb="$(df -Pm "${iso_dir}" | awk 'NR==2 {print $4}')"

  if [[ -z "${avail_mb}" ]]; then
    echo "Warning: failed to detect free space for ${iso_dir}; continuing."
    return
  fi

  if (( avail_mb < MIN_ISO_FREE_MB )); then
    echo "Error: free space is too low for ISO download."
    echo "- Target dir : ${iso_dir}"
    echo "- Free space : ${avail_mb} MB"
    echo "- Required   : >= ${MIN_ISO_FREE_MB} MB (tunable via MIN_ISO_FREE_MB)"
    echo
    df -h "${iso_dir}" || true
    echo
    echo "Tips:"
    echo "1) Remove old files in ${BASE_DIR} (old .iso/.qcow2)."
    echo "2) Use a larger path: BASE_DIR='/path/with-more-space' or ISO_PATH='/path/windows.iso'."
    echo "3) Reduce qcow2 target size if needed: DISK_GB=40 (or lower as needed)."
    exit 1
  fi
}

prepare_iso() {
  if [[ -f "${ISO_PATH}" ]]; then
    if [[ -n "${ISO_URL}" && -f "${ISO_SOURCE_MARKER}" ]]; then
      if [[ "$(cat "${ISO_SOURCE_MARKER}")" == "${ISO_URL}" ]]; then
        echo "Windows ISO found (source matches requested URL): ${ISO_PATH}"
        return
      fi

      echo "Existing ISO source differs from requested URL; replacing file."
      rm -f "${ISO_PATH}"
    elif [[ -n "${ISO_URL}" ]]; then
      echo "Existing ISO found but source is unknown; replacing to avoid wrong ISO."
      rm -f "${ISO_PATH}"
    else
      echo "Windows ISO found: ${ISO_PATH}"
      return
    fi
  fi

  if [[ -z "${ISO_URL}" ]]; then
    echo "Error: ISO not found and ISO_URL not set."
    echo "Place ISO at ${ISO_PATH} or export ISO_URL='https://.../windows.iso'"
    exit 1
  fi

  check_iso_target_free_space

  if is_mega_url "${ISO_URL}"; then
    download_from_mega "${ISO_URL}"
  elif is_google_drive_url "${ISO_URL}"; then
    download_from_gdrive "${ISO_URL}"
  else
    echo "Downloading Windows ISO..."
    wget -O "${ISO_PATH}" "${ISO_URL}"
  fi

  if [[ -n "${ISO_URL}" ]]; then
    printf '%s' "${ISO_URL}" > "${ISO_SOURCE_MARKER}"
  fi
}

prepare_disk() {
  if [[ -f "${DISK_PATH}" ]]; then
    echo "Disk already exists: ${DISK_PATH}"
  else
    echo "Creating qcow2 disk (${DISK_GB}G): ${DISK_PATH}"
    qemu-img create -f qcow2 "${DISK_PATH}" "${DISK_GB}G"
  fi
}

write_unattend() {
  cat > "${AUTOUNATTEND_XML}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage>
        <UILanguage>en-US</UILanguage>
      </SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DiskConfiguration>
        <Disk wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Type>Primary</Type>
              <Size>100</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Type>Primary</Type>
              <Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Format>NTFS</Format>
              <Label>System</Label>
              <Active>true</Active>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
              <Format>NTFS</Format>
              <Label>Windows</Label>
              <Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallToAvailablePartition>true</InstallToAvailablePartition>
          <WillShowUI>OnError</WillShowUI>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey>
          <WillShowUI>Never</WillShowUI>
        </ProductKey>
        <FullName>${WIN_USER}</FullName>
        <Organization>AutoInstall</Organization>
      </UserData>
    </component>
  </settings>

  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>${VM_NAME}</ComputerName>
      <TimeZone>${TIMEZONE}</TimeZone>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>

    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>

      <UserAccounts>
        <AdministratorPassword>
          <Value>${WIN_ADMIN_PASSWORD}</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>

      <AutoLogon>
        <Enabled>true</Enabled>
        <LogonCount>2</LogonCount>
        <Username>${WIN_USER}</Username>
        <Password>
          <Value>${WIN_ADMIN_PASSWORD}</Value>
          <PlainText>true</PlainText>
        </Password>
      </AutoLogon>

      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>1</Order>
          <Description>Enable RDP</Description>
          <CommandLine>cmd /c reg add "HKLM\\System\\CurrentControlSet\\Control\\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>2</Order>
          <Description>Open RDP firewall</Description>
          <CommandLine>cmd /c netsh advfirewall firewall set rule group="remote desktop" new enable=Yes</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>3</Order>
          <Description>Allow TCP 3389 explicitly</Description>
          <CommandLine>cmd /c netsh advfirewall firewall add rule name="RDP-TCP-3389" dir=in action=allow protocol=TCP localport=3389</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>4</Order>
          <Description>Ensure TermService is running</Description>
          <CommandLine>cmd /c sc config TermService start= auto &amp; net start TermService</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>5</Order>
          <Description>Disable NLA for compatibility</Description>
          <CommandLine>cmd /c reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\WinStations\\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>

  <cpi:offlineImage cpi:source="wim:c:/sources/install.wim#Windows" xmlns:cpi="urn:schemas-microsoft-com:cpi" />
</unattend>
EOF

  genisoimage -quiet -o "${AUTOUNATTEND_ISO}" -J -R "${AUTOUNATTEND_XML}"
}

start_installer_vm() {
  if [[ -f "${QEMU_PIDFILE}" ]] && kill -0 "$(cat "${QEMU_PIDFILE}")" 2>/dev/null; then
    echo "Installer VM already running (pid $(cat "${QEMU_PIDFILE}"))."
    return
  fi

  qemu-system-x86_64 \
    -name "${VM_NAME}-install" \
    -machine type="${VM_MACHINE}",accel=kvm:tcg \
    -cpu host \
    -smp "${VM_CPUS}" \
    -m "${VM_RAM_MB}" \
    -drive file="${DISK_PATH}",if=ide,cache=writeback,discard=unmap,format=qcow2 \
    -drive file="${ISO_PATH}",media=cdrom,if=ide \
    -drive file="${AUTOUNATTEND_ISO}",media=cdrom,if=ide,readonly=on \
    -boot order=d,once=d \
    -netdev user,id=net0,hostfwd=tcp::"${RDP_HOST_PORT}"-:3389 \
    -device e1000,netdev=net0 \
    -vnc 0.0.0.0:"${VNC_DISPLAY}" \
    -display none \
    -daemonize \
    -pidfile "${QEMU_PIDFILE}"

  cat <<MSG

Installer VM started.
- VNC        : <droplet-ip>:$((5900 + VNC_DISPLAY))
- RDP (after install): <droplet-ip>:${RDP_HOST_PORT}
- Disk       : ${DISK_PATH}

Tips:
1) Keep installer running until Windows setup + reboot completes.
2) After installation, stop installer process and run start_windows_vm.sh for normal boot.
MSG
}

main() {
  resolve_iso_source

  echo "==> Installing required packages"
  apt_install

  echo "==> Preparing ISO"
  prepare_iso

  echo "==> Preparing disk"
  prepare_disk

  echo "==> Generating Autounattend ISO"
  write_unattend

  echo "==> Starting unattended installer"
  start_installer_vm
}

main "$@"

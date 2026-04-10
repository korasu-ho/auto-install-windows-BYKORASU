#!/usr/bin/env bash
set -euo pipefail

# Build a DigitalOcean-compatible Windows image using VirtIO storage/network drivers.
# This script prepares ISO files, creates a RAW disk, and starts a QEMU installer VM.
# For Windows choices 1-3, unattended mode can auto-load VirtIO drivers and install guest tools.

if [[ ${EUID} -ne 0 ]]; then
  echo "Error: run as root (sudo)."
  exit 1
fi

VM_NAME="${VM_NAME:-winvm}"
BASE_DIR="${BASE_DIR:-/opt/${VM_NAME}}"
WIN_VERSION_CHOICE="${WIN_VERSION_CHOICE:-3}"
AUTO_INSTALL="${AUTO_INSTALL:-true}"
AUTO_SHUTDOWN_AFTER_SETUP="${AUTO_SHUTDOWN_AFTER_SETUP:-false}"
WIN_ADMIN_PASSWORD="${WIN_ADMIN_PASSWORD:-ChangeMe123!}"
TIMEZONE="${TIMEZONE:-SE Asia Standard Time}"
ISO_URL="${ISO_URL:-}"
ISO_PATH="${ISO_PATH:-}"
FORCE_ISO_DOWNLOAD="${FORCE_ISO_DOWNLOAD:-false}"
VIRTIO_ISO_URL="${VIRTIO_ISO_URL:-https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso}"
VIRTIO_ISO_PATH="${VIRTIO_ISO_PATH:-${BASE_DIR}/virtio-win.iso}"
RAW_IMG_PATH="${RAW_IMG_PATH:-${BASE_DIR}/${VM_NAME}-do-virtio.img}"
DISK_GB="${DISK_GB:-64}"
VM_CPUS="${VM_CPUS:-4}"
VM_RAM_MB="${VM_RAM_MB:-6144}"
RDP_HOST_PORT="${RDP_HOST_PORT:-3389}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"
BUILDER_DISK_IF="${BUILDER_DISK_IF:-virtio}" # virtio|ide
AUTO_SAFE_DISK_IF="${AUTO_SAFE_DISK_IF:-true}" # if true, AUTO_INSTALL may switch installer disk IF to ide for stability
PIDFILE="${BASE_DIR}/qemu-do-builder.pid"
AUTOUNATTEND_XML="${BASE_DIR}/Autounattend-do.xml"
AUTOUNATTEND_ISO="${BASE_DIR}/autounattend-do.iso"
AUTOUNATTEND_STAGING_DIR="${BASE_DIR}/autounattend-staging"

WIN_USER="Administrator"
WIN_LABEL="Windows"
WIN_IMAGE_NAME="${WIN_IMAGE_NAME:-}"
WIN_IMAGE_INDEX="${WIN_IMAGE_INDEX:-}"

mkdir -p "${BASE_DIR}"

show_status() {
  echo "== DO-Compatible Builder Status =="
  echo "VM_NAME          : ${VM_NAME}"
  echo "BASE_DIR         : ${BASE_DIR}"
  echo "RAW_IMG_PATH     : ${RAW_IMG_PATH}"
  echo "ISO_PATH         : ${ISO_PATH:-<not-set>}"
  echo "VIRTIO_ISO_PATH  : ${VIRTIO_ISO_PATH}"
  echo "AUTOUNATTEND_ISO : ${AUTOUNATTEND_ISO}"
  echo "PIDFILE          : ${PIDFILE}"
  echo

  if [[ -f "${ISO_PATH:-/nonexistent}" ]]; then
    ls -lh "${ISO_PATH}"
  else
    echo "[WARN] Windows ISO not found at configured path."
  fi

  if [[ -f "${VIRTIO_ISO_PATH}" ]]; then
    ls -lh "${VIRTIO_ISO_PATH}"
  else
    echo "[WARN] VirtIO ISO not found."
  fi

  if [[ -f "${RAW_IMG_PATH}" ]]; then
    ls -lh "${RAW_IMG_PATH}"
    qemu-img info "${RAW_IMG_PATH}" || true
  else
    echo "[WARN] RAW image not found."
  fi

  if [[ -f "${AUTOUNATTEND_ISO}" ]]; then
    ls -lh "${AUTOUNATTEND_ISO}"
  else
    echo "[INFO] Autounattend ISO not generated yet (or AUTO_INSTALL=false)."
  fi

  if [[ -f "${PIDFILE}" ]] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
    echo "[OK] Builder VM running (pid $(cat "${PIDFILE}"))"
  else
    echo "[INFO] Builder VM is not running."
  fi
}

set_windows_iso_by_choice() {
  case "${WIN_VERSION_CHOICE}" in
    1)
      ISO_URL="https://go.microsoft.com/fwlink/p/?LinkID=2195174&clcid=0x409&culture=en-us&country=US"
      ISO_PATH="${BASE_DIR}/windows2016.iso"
      if [[ -z "${WIN_IMAGE_NAME}" ]]; then
        WIN_IMAGE_NAME="Windows Server 2016 Datacenter Evaluation (Desktop Experience)"
      fi
      if [[ -z "${WIN_IMAGE_INDEX}" ]]; then
        WIN_IMAGE_INDEX="4"
      fi
      ;;
    2)
      ISO_URL="https://go.microsoft.com/fwlink/p/?LinkID=2195167&clcid=0x409&culture=en-us&country=US"
      ISO_PATH="${BASE_DIR}/windows2019.iso"
      if [[ -z "${WIN_IMAGE_NAME}" ]]; then
        WIN_IMAGE_NAME="Windows Server 2019 Datacenter Evaluation (Desktop Experience)"
      fi
      if [[ -z "${WIN_IMAGE_INDEX}" ]]; then
        WIN_IMAGE_INDEX="4"
      fi
      ;;
    3)
      ISO_URL="https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
      ISO_PATH="${BASE_DIR}/windows2022.iso"
      if [[ -z "${WIN_IMAGE_NAME}" ]]; then
        WIN_IMAGE_NAME="Windows Server 2022 Datacenter Evaluation (Desktop Experience)"
      fi
      if [[ -z "${WIN_IMAGE_INDEX}" ]]; then
        WIN_IMAGE_INDEX="4"
      fi
      ;;
    4)
      if [[ -z "${ISO_URL}" ]]; then
        echo "Error: WIN_VERSION_CHOICE=4 requires ISO_URL"
        exit 1
      fi
      if [[ -z "${ISO_PATH}" ]]; then
        ISO_PATH="${BASE_DIR}/windows-custom.iso"
      fi
      if [[ -z "${WIN_IMAGE_NAME}" ]]; then
        WIN_IMAGE_NAME="Windows Server 2022 Datacenter Evaluation (Desktop Experience)"
      fi
      if [[ -z "${WIN_IMAGE_INDEX}" ]]; then
        WIN_IMAGE_INDEX="4"
      fi
      ;;
    *)
      echo "Error: invalid WIN_VERSION_CHOICE=${WIN_VERSION_CHOICE}. Use 1/2/3/4"
      exit 1
      ;;
  esac
}

virtio_os_tag() {
  case "${WIN_VERSION_CHOICE}" in
    1) echo "2k16" ;;
    2) echo "2k19" ;;
    3) echo "2k22" ;;
    *) echo "2k22" ;;
  esac
}

bool_is_true() {
  [[ "$1" == "true" || "$1" == "1" || "$1" == "yes" ]]
}

resolve_builder_disk_if() {
  if ! bool_is_true "${AUTO_SAFE_DISK_IF}"; then
    echo "${BUILDER_DISK_IF}"
    return
  fi

  # Windows setup in unattended mode can fail with ImageInstall on some builds
  # when storage is attached as virtio too early. IDE is used only for install
  # stage; VirtIO tools/drivers are still injected for native compatibility.
  if bool_is_true "${AUTO_INSTALL}"; then
    case "${WIN_VERSION_CHOICE}" in
      1|2|3)
        echo "ide"
        return
        ;;
    esac
  fi

  echo "${BUILDER_DISK_IF}"
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y qemu-system-x86 qemu-utils genisoimage curl wget
}

download_if_missing() {
  local url="$1"
  local path="$2"

  if [[ -f "${path}" ]] && bool_is_true "${FORCE_ISO_DOWNLOAD}"; then
    echo "Re-downloading (FORCE_ISO_DOWNLOAD=true): ${path}"
    wget -O "${path}" "${url}"
    return
  fi

  if [[ -f "${path}" ]]; then
    echo "Found: ${path}"
    return
  fi
  echo "Downloading: ${url}"
  wget -O "${path}" "${url}"
}

prepare_disk() {
  if [[ -f "${RAW_IMG_PATH}" ]]; then
    echo "RAW image already exists: ${RAW_IMG_PATH}"
  else
    echo "Creating RAW image ${DISK_GB}G: ${RAW_IMG_PATH}"
    qemu-img create -f raw "${RAW_IMG_PATH}" "${DISK_GB}G"
  fi
}

write_unattend() {
  local os_tag
  os_tag="$(virtio_os_tag)"

  local shutdown_cmd=""
  if bool_is_true "${AUTO_SHUTDOWN_AFTER_SETUP}"; then
    shutdown_cmd=$(cat <<'EOF'
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>7</Order>
          <Description>Auto shutdown after setup</Description>
          <CommandLine>cmd /c shutdown /s /t 30</CommandLine>
        </SynchronousCommand>
EOF
)
  fi

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

    <component name="Microsoft-Windows-PnpCustomizationsWinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DriverPaths>
        <PathAndCredentials wcm:action="add" wcm:keyValue="1" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>D:\viostor\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="2" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>D:\vioscsi\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="3" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>E:\viostor\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="4" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>E:\vioscsi\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="5" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>F:\viostor\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="6" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>F:\vioscsi\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="7" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>G:\viostor\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="8" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>G:\vioscsi\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="9" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>H:\viostor\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="10" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>H:\vioscsi\${os_tag}\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="11" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>D:\viostor\w10\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="12" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>D:\vioscsi\w10\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="13" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>E:\viostor\w10\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="14" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>E:\vioscsi\w10\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="15" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>F:\viostor\w10\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="16" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>F:\vioscsi\w10\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="17" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>G:\viostor\w10\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="18" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>G:\vioscsi\w10\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="19" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>H:\viostor\w10\amd64</Path>
        </PathAndCredentials>
        <PathAndCredentials wcm:action="add" wcm:keyValue="20" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Path>H:\vioscsi\w10\amd64</Path>
        </PathAndCredentials>
      </DriverPaths>
    </component>

    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
              <Key>/IMAGE/INDEX</Key>
              <Value>${WIN_IMAGE_INDEX}</Value>
            </MetaData>
            <MetaData wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
              <Key>/IMAGE/NAME</Key>
              <Value>${WIN_IMAGE_NAME}</Value>
            </MetaData>
          </InstallFrom>
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
          <Description>Install VirtIO guest tools</Description>
          <CommandLine>cmd /c for %L in (D E F G H) do if exist %L:\virtio-win-guest-tools.exe start /wait "" %L:\virtio-win-guest-tools.exe /qn /norestart</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>2</Order>
          <Description>Enable RDP</Description>
          <CommandLine>cmd /c reg add "HKLM\\System\\CurrentControlSet\\Control\\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>3</Order>
          <Description>Open RDP firewall</Description>
          <CommandLine>cmd /c netsh advfirewall firewall set rule group="remote desktop" new enable=Yes</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>4</Order>
          <Description>Allow TCP 3389</Description>
          <CommandLine>cmd /c netsh advfirewall firewall add rule name="RDP-TCP-3389" dir=in action=allow protocol=TCP localport=3389</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>5</Order>
          <Description>Ensure TermService</Description>
          <CommandLine>cmd /c sc config TermService start= auto &amp; net start TermService</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>6</Order>
          <Description>Enable VirtIO storage drivers at boot</Description>
          <CommandLine>cmd /c reg add "HKLM\SYSTEM\CurrentControlSet\Services\viostor" /v Start /t REG_DWORD /d 0 /f &amp; reg add "HKLM\SYSTEM\CurrentControlSet\Services\vioscsi" /v Start /t REG_DWORD /d 0 /f</CommandLine>
        </SynchronousCommand>
${shutdown_cmd}
      </FirstLogonCommands>
    </component>
  </settings>

  <cpi:offlineImage cpi:source="wim:c:/sources/install.wim#${WIN_LABEL}" xmlns:cpi="urn:schemas-microsoft-com:cpi" />
</unattend>
EOF

  rm -rf "${AUTOUNATTEND_STAGING_DIR}"
  mkdir -p "${AUTOUNATTEND_STAGING_DIR}"
  cp "${AUTOUNATTEND_XML}" "${AUTOUNATTEND_STAGING_DIR}/Autounattend.xml"
  genisoimage -quiet -o "${AUTOUNATTEND_ISO}" -J -R "${AUTOUNATTEND_STAGING_DIR}/Autounattend.xml"
}

start_builder_vm() {
  local disk_arg
  local effective_disk_if

  effective_disk_if="$(resolve_builder_disk_if)"

  case "${effective_disk_if}" in
    virtio)
      disk_arg="-drive file=${RAW_IMG_PATH},if=virtio,format=raw,cache=writeback,discard=unmap"
      ;;
    ide)
      disk_arg="-drive file=${RAW_IMG_PATH},if=ide,format=raw,cache=writeback,discard=unmap"
      ;;
    *)
      echo "Error: invalid disk interface mode=${effective_disk_if}. Use virtio or ide."
      exit 1
      ;;
  esac

  if [[ -f "${PIDFILE}" ]] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
    echo "Builder VM already running (pid $(cat "${PIDFILE}"))."
    return
  fi

  qemu-system-x86_64 \
    -name "${VM_NAME}-do-builder" \
    -machine type=pc,accel=kvm:tcg \
    -cpu host \
    -smp "${VM_CPUS}" \
    -m "${VM_RAM_MB}" \
    ${disk_arg} \
    -drive file="${ISO_PATH}",media=cdrom,if=ide \
    -drive file="${VIRTIO_ISO_PATH}",media=cdrom,if=ide \
    ${AUTO_DRIVE_ARG} \
    -boot order=d \
    -netdev user,id=net0,hostfwd=tcp::"${RDP_HOST_PORT}"-:3389 \
    -device virtio-net-pci,netdev=net0 \
    -vnc 0.0.0.0:"${VNC_DISPLAY}" \
    -display none \
    -daemonize \
    -pidfile "${PIDFILE}"

  cat <<MSG

Builder VM started.
- VNC: <droplet-ip>:$((5900 + VNC_DISPLAY))
- RDP forward after guest setup: <droplet-ip>:${RDP_HOST_PORT}
- Disk image: ${RAW_IMG_PATH}

Mode AUTO_INSTALL=${AUTO_INSTALL}
Disk IF requested=${BUILDER_DISK_IF}
Disk IF effective=${effective_disk_if}

If AUTO_INSTALL=true (recommended for choices 1-3):
1) Setup should run mostly unattended.
2) VirtIO guest tools + RDP configuration run automatically at first logon.
3) Verify Windows reached desktop and networking is up.
4) Shutdown guest cleanly before export.

If setup fails with disk/partition unattended errors:
1) Stop builder VM.
2) Retry with IDE fallback:
  sudo AUTO_INSTALL=true WIN_VERSION_CHOICE=${WIN_VERSION_CHOICE} BUILDER_DISK_IF=ide ./build_do_compatible_image.sh
3) Keep VirtIO ISO attached (already handled by this script) and proceed normally.

If AUTO_INSTALL=false (manual mode):
1) At disk selection, click "Load driver".
2) Open VirtIO CD and load storage driver matching OS version (viostor/vioscsi, amd64).
3) Continue installation to the VirtIO disk.
4) After first login, run "virtio-win-guest-tools.exe" manually.
5) Enable RDP manually, then shutdown guest.

After that, run export_do_compatible_image.sh to create .img.gz for native deploy.

Tip:
- If AUTO_INSTALL stops at edition selection, set WIN_IMAGE_NAME explicitly, e.g.:
  WIN_IMAGE_NAME='Windows Server 2022 Datacenter Evaluation (Desktop Experience)'
- You can also set WIN_IMAGE_INDEX explicitly (common for Datacenter Desktop Experience: 4).
MSG
}

main() {
  if [[ "${1:-}" == "--status" ]]; then
    set_windows_iso_by_choice
    show_status
    return
  fi

  set_windows_iso_by_choice
  apt_install
  download_if_missing "${ISO_URL}" "${ISO_PATH}"
  download_if_missing "${VIRTIO_ISO_URL}" "${VIRTIO_ISO_PATH}"
  AUTO_DRIVE_ARG=""
  if bool_is_true "${AUTO_INSTALL}"; then
    write_unattend
    AUTO_DRIVE_ARG="-drive file=${AUTOUNATTEND_ISO},media=cdrom,if=ide,readonly=on"
  fi
  prepare_disk
  start_builder_vm
}

main "$@"

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
DISK_PATH="${DISK_PATH:-${BASE_DIR}/${VM_NAME}.qcow2}"
DISK_GB="${DISK_GB:-64}"
VM_CPUS="${VM_CPUS:-4}"
VM_RAM_MB="${VM_RAM_MB:-6144}"
RDP_HOST_PORT="${RDP_HOST_PORT:-3389}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"  # VNC port = 5900 + display
WIN_ADMIN_PASSWORD="${WIN_ADMIN_PASSWORD:-ChangeMe123!}"
TIMEZONE="${TIMEZONE:-SE Asia Standard Time}"

# Windows unattended account name. Keep Administrator for easiest RDP setup.
WIN_USER="Administrator"
AUTOUNATTEND_XML="${BASE_DIR}/Autounattend.xml"
AUTOUNATTEND_ISO="${BASE_DIR}/autounattend.iso"
QEMU_PIDFILE="${BASE_DIR}/qemu-install.pid"

mkdir -p "${BASE_DIR}"

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    genisoimage \
    curl \
    wget
}

prepare_iso() {
  if [[ -f "${ISO_PATH}" ]]; then
    echo "Windows ISO found: ${ISO_PATH}"
    return
  fi

  if [[ -z "${ISO_URL}" ]]; then
    echo "Error: ISO not found and ISO_URL not set."
    echo "Place ISO at ${ISO_PATH} or export ISO_URL='https://.../windows.iso'"
    exit 1
  fi

  echo "Downloading Windows ISO..."
  wget -O "${ISO_PATH}" "${ISO_URL}"
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
      <ImageInstall>
        <OSImage>
          <InstallToAvailablePartition>true</InstallToAvailablePartition>
          <WillShowUI>OnError</WillShowUI>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
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
    -machine type=q35,accel=kvm:tcg \
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

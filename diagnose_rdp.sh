#!/usr/bin/env bash
set -euo pipefail

# Quick diagnostics for Windows VM RDP forwarding on a Linux host.

VM_NAME="${VM_NAME:-winvm}"
BASE_DIR="${BASE_DIR:-/opt/${VM_NAME}}"
RDP_HOST_PORT="${RDP_HOST_PORT:-3389}"
RUN_PIDFILE="${BASE_DIR}/qemu-run.pid"
INSTALL_PIDFILE="${BASE_DIR}/qemu-install.pid"

line() {
  printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '-'
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

show_pid_status() {
  local label="$1"
  local pidfile="$2"

  if [[ -f "$pidfile" ]]; then
    local pid
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "[OK] ${label}: running (pid=${pid})"
    else
      echo "[WARN] ${label}: pidfile exists but process is not running (${pidfile})"
    fi
  else
    echo "[INFO] ${label}: not running (pidfile not found)"
  fi
}

check_listen_port() {
  if has_cmd ss; then
    local out
    out="$(ss -ltnp 2>/dev/null | grep -E ":${RDP_HOST_PORT}[[:space:]]" || true)"
    if [[ -n "$out" ]]; then
      echo "[OK] Host is listening on TCP ${RDP_HOST_PORT}"
      echo "$out"
    else
      echo "[WARN] Nothing is listening on TCP ${RDP_HOST_PORT}"
    fi
  else
    echo "[INFO] Command 'ss' not found; skipping listen-port check"
  fi
}

check_local_tcp_connect() {
  if has_cmd nc; then
    if nc -z -w 2 127.0.0.1 "$RDP_HOST_PORT"; then
      echo "[OK] Local TCP connect to 127.0.0.1:${RDP_HOST_PORT} succeeded"
    else
      echo "[WARN] Local TCP connect to 127.0.0.1:${RDP_HOST_PORT} failed"
    fi
  else
    echo "[INFO] Command 'nc' not found; skipping local TCP connect test"
  fi
}

check_ufw() {
  if has_cmd ufw; then
    local status
    status="$(ufw status 2>/dev/null || true)"
    echo "[INFO] UFW status:"
    echo "$status"
    if ! echo "$status" | grep -q "${RDP_HOST_PORT}"; then
      echo "[WARN] UFW rule for ${RDP_HOST_PORT} not detected"
    fi
  else
    echo "[INFO] UFW not installed; skipping"
  fi
}

show_hint() {
  line
  echo "Next checks from your local Windows PC:"
  echo "1) Test TCP reachability:  Test-NetConnection <DROPLET_IP> -Port ${RDP_HOST_PORT}"
  echo "2) If failed, open DigitalOcean Cloud Firewall inbound TCP ${RDP_HOST_PORT}"
  echo "3) If TCP works but RDP auth fails, verify Windows password and try mstsc /admin"
  echo "4) If still blocked, reconnect via VNC and verify inside Windows:"
  echo "   - TermService is running"
  echo "   - Windows Firewall allows Remote Desktop"
  echo "   - Registry fDenyTSConnections=0"
}

line
echo "RDP Diagnostics for VM: ${VM_NAME}"
echo "Base dir: ${BASE_DIR}"
echo "Host RDP port: ${RDP_HOST_PORT}"
line

show_pid_status "Runtime VM" "$RUN_PIDFILE"
show_pid_status "Installer VM" "$INSTALL_PIDFILE"

line
check_listen_port
check_local_tcp_connect

line
check_ufw

show_hint

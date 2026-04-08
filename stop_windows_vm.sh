#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:-winvm}"
BASE_DIR="${BASE_DIR:-/opt/${VM_NAME}}"
RUN_PIDFILE="${BASE_DIR}/qemu-run.pid"
INSTALL_PIDFILE="${BASE_DIR}/qemu-install.pid"

stop_pidfile() {
  local pidfile="$1"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid="$(cat "$pidfile")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "Stopped process pid=$pid"
    else
      echo "Process already stopped (pid=$pid)"
    fi
    rm -f "$pidfile"
  fi
}

stop_pidfile "$RUN_PIDFILE"
stop_pidfile "$INSTALL_PIDFILE"

echo "Done."

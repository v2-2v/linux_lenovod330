#!/bin/bash
# Usage: d330-set-idle-timeout <minutes>|off
# Changes how long the D330 waits with no keyboard/mouse activity before
# turning the backlight off. Takes effect within ~2 seconds, no restart needed.
# "off" disables idle auto-off entirely (stops the systemd --user service);
# lid close/open handling (acpid) is separate and keeps working either way.
set -euo pipefail

usage() {
  echo "usage: $0 <minutes>|off  (minutes must be a positive integer, e.g. 5)" >&2
  exit 1
}

[ $# -eq 1 ] || usage

if [ "$1" = "off" ]; then
  systemctl --user disable --now d330-backlight-idle.service
  echo "idle auto-off disabled (lid close/open still works)."
  exit 0
fi

[[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] || usage

mkdir -p "$HOME/.config"
echo "IDLE_MINUTES=$1" > "$HOME/.config/d330-backlight-idle.conf"
systemctl --user enable --now d330-backlight-idle.service
echo "idle timeout set to $1 minute(s)."

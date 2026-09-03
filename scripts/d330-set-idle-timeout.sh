#!/bin/bash
# Usage: d330-set-idle-timeout <minutes>
# Changes how long the D330 waits with no keyboard/mouse activity before
# turning the backlight off. Takes effect within ~2 seconds, no restart needed.
set -euo pipefail

if [ $# -ne 1 ] || ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ]; then
  echo "usage: $0 <minutes>  (positive integer, e.g. 5)" >&2
  exit 1
fi

mkdir -p "$HOME/.config"
echo "IDLE_MINUTES=$1" > "$HOME/.config/d330-backlight-idle.conf"
echo "idle timeout set to $1 minute(s)."

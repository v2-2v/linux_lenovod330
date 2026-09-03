#!/bin/bash
# D330: physically cut/restore the DSI panel backlight-enable GPIO (VBT index 4,
# PANEL1_BKLTEN) via the custom i915 module param d330_backlight_gpio, WITHOUT
# touching DPMS/CRTC state or the panel power rail (index 3). See the project
# README for why this avoids the known black-screen-after-DPMS/suspend bug.
set -euo pipefail

PARAM=/sys/module/i915/parameters/d330_backlight_gpio

case "${1:-}" in
  off) echo 0 > "$PARAM" ;;
  on)  echo 1 > "$PARAM" ;;
  *)
    echo "usage: $0 {off|on}" >&2
    exit 1
    ;;
esac

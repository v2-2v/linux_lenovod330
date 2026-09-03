#!/bin/bash
# D330: instant, event-driven backlight off/on on lid close/open via acpid.
# Runs as root (acpid). Reads lid state directly rather than trusting the
# acpi event payload, since payload format varies by firmware.
STATE=$(cat /proc/acpi/button/lid/*/state 2>/dev/null | awk '{print $2}')

case "$STATE" in
  closed) /usr/local/bin/d330-backlight.sh off ;;
  open)   /usr/local/bin/d330-backlight.sh on ;;
esac

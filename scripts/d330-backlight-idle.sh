#!/bin/bash
# D330: idle-triggered backlight-only screen off (no DPMS, no suspend).
# Runs as an unprivileged user (systemd --user service); toggles backlight via
# passwordless sudo restricted to d330-backlight.sh only (see the sudoers.d
# snippet in README.md).
#
# Idle timeout is configurable at runtime via ~/.config/d330-backlight-idle.conf
# (re-read every poll, so a change takes effect within a couple of seconds --
# no need to restart the service). Set it with: d330-set-idle-timeout <minutes>
CONF="$HOME/.config/d330-backlight-idle.conf"
POLL_S=2

state=on
while true; do
  IDLE_MINUTES=5
  [ -f "$CONF" ] && . "$CONF"
  idle_off_ms=$(( IDLE_MINUTES * 60000 ))

  if ! command -v xprintidle >/dev/null 2>&1; then
    # Don't silently fall back to "idle=0" forever -- that makes idle
    # auto-off a permanent, invisible no-op. Log (visible via
    # `journalctl --user -u d330-backlight-idle.service`) and retry next
    # poll; installing xprintidle later self-heals with no restart needed.
    echo "d330-backlight-idle: xprintidle not found -- idle auto-off is inactive until it's installed (sudo apt-get install xprintidle)" >&2
    sleep "$POLL_S"
    continue
  fi

  idle=$(xprintidle 2>/dev/null) || { sleep "$POLL_S"; continue; }
  if [ "$idle" -ge "$idle_off_ms" ] && [ "$state" = on ]; then
    sudo -n /usr/local/bin/d330-backlight.sh off
    state=off
  elif [ "$idle" -lt "$idle_off_ms" ] && [ "$state" = off ]; then
    sudo -n /usr/local/bin/d330-backlight.sh on
    state=on
  fi
  sleep "$POLL_S"
done

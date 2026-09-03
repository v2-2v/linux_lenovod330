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

  idle=$(xprintidle 2>/dev/null || echo 0)
  if [ "$idle" -ge "$idle_off_ms" ] && [ "$state" = on ]; then
    sudo -n /usr/local/bin/d330-backlight.sh off
    state=off
  elif [ "$idle" -lt "$idle_off_ms" ] && [ "$state" = off ]; then
    sudo -n /usr/local/bin/d330-backlight.sh on
    state=on
  fi
  sleep "$POLL_S"
done

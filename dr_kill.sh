#!/bin/bash

# Whitelisted process names
WHITELIST=(
  systemd
  init
  bash
  sshd
  dbus-daemon
  systemd-logind
  system-journald
  NetworkManager
 )

# Add current scripts shell
WHITELIST+=("$$")

# Create regex pattern from whitelist
pattern=$(printf "|%s" "${WHITELIST[@]}")
pattern=${pattern:1}

echo "=== DRY RUN: displaying actions only ==="
echo

ps -eo pid,comm | tail -n +2 | while read pid comm; do
    if [[ "$comm" =~ ^($pattern)$ ]]; then
        echo "SAFE:   $pid ($comm)"
    else
        echo "KILL?: $pid ($comm)"
    fi
done

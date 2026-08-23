#!/bin/bash
# lidawake uninstaller — restores stock macOS behaviour and removes everything.
set -uo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
BINDIR="${LIDAWAKE_BINDIR:-$HOME/.local/bin}"
LABEL=cc.openq.lidawake
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "Restoring stock behaviour…"
"$REPO/bin/lidawake" normal 2>/dev/null || sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null

echo "Stopping daemon…"
launchctl unload "$PLIST" 2>/dev/null; rm -f "$PLIST"

echo "Removing symlinks…"
for f in lidawake lidtest dispbright; do
  [ -L "$BINDIR/$f" ] && rm -f "$BINDIR/$f" && echo "  $BINDIR/$f"
done

echo "Removing sudoers rule (needs your password)…"
sudo rm -f /etc/sudoers.d/lidawake && echo "  /etc/sudoers.d/lidawake"

echo
echo "State kept at ~/.local/state/lidawake (delete manually if you want it gone)."
echo "Verify: ioreg -c IOPMrootDomain -r -d 1 | grep SleepDisabled   # expect: No"

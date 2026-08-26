#!/bin/bash
# lidawake installer — run from the cloned repo:  ./install.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
BINDIR="${LIDAWAKE_BINDIR:-$HOME/.local/bin}"
SUDOERS=/etc/sudoers.d/lidawake

say(){ printf '\033[1m%s\033[0m\n' "$*"; }
die(){ printf 'error: %s\n' "$*" >&2; exit 1; }

say "lidawake $("$(cd "$(dirname "$0")" && pwd)/bin/lidawake" --version 2>/dev/null | awk '{print $2}')"
say "1/5  Checking environment"
[ "$(uname -s)" = Darwin ] || die "macOS only."
command -v clang >/dev/null || die "clang not found. Install the Xcode Command Line Tools: xcode-select --install"
sw_vers -productVersion | sed 's/^/      macOS /'
printf '      arch %s\n' "$(uname -m)"

say "2/5  Building dispbright"
clang -O2 -o "$REPO/bin/dispbright" "$REPO/src/dispbright.c" -framework CoreGraphics
"$REPO/bin/dispbright" >/dev/null || die "dispbright built but cannot read brightness."
printf '      ok (current brightness %s)\n' "$("$REPO/bin/dispbright")"

say "3/5  Linking into $BINDIR"
mkdir -p "$BINDIR"
for f in lidawake lidtest dispbright; do
  [ -e "$REPO/bin/$f" ] || continue
  ln -sf "$REPO/bin/$f" "$BINDIR/$f"; printf '      %s -> %s\n' "$BINDIR/$f" "$REPO/bin/$f"
done
case ":$PATH:" in *":$BINDIR:"*) : ;; *) printf '      NOTE: %s is not on your PATH — add it to your shell profile.\n' "$BINDIR" ;; esac

say "4/5  Installing the sudoers rule (needs your password)"
# Test for the file, not for `sudo -n` success: sudo caches credentials for a
# few minutes, so right after any other sudo command the -n probe succeeds even
# when the rule is gone. That is exactly the uninstall-then-reinstall path.
if [ -f "$SUDOERS" ]; then
  printf '      already in place, skipping\n'
else
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  sed "s/__USER__/$(id -un)/" "$REPO/share/sudoers.in" > "$tmp"
  chmod 0440 "$tmp"
  visudo -c -f "$tmp" >/dev/null || die "generated sudoers file failed validation; nothing was installed."
  printf '      This grants passwordless sudo for these three commands ONLY:\n'
  sed 's/^/        /' "$tmp" | grep -v '^        #'
  sudo install -m 0440 -o root -g wheel "$tmp" "$SUDOERS"
  sudo -n /usr/bin/pmset -g >/dev/null 2>&1 || die "rule installed but not effective."
  printf '      installed to %s\n' "$SUDOERS"
fi

say "5/5  Starting the daemon"
"$REPO/bin/lidawake" auto

cat <<'TXT'

Done. Try:
  lidawake status
  lidawake toggle

Optional — Raycast commands:
  Raycast Settings -> search "script" -> Script Commands -> add directory:
TXT
printf '    %s/raycast\n\n' "$REPO"

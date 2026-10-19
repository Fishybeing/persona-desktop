#!/usr/bin/env bash
# Makes PersonaDesktop-log.zip on the Desktop with what's needed to figure out a problem. Your user name is removed.
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/persona-desktop"
desk="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
tmp="$(mktemp -d)"
out="$tmp/PersonaDesktop-log"
mkdir -p "$out"
echo "Collecting the log..."
{
  echo "== system"; uname -a; cat /etc/os-release 2>/dev/null | head -n 4
  echo "session: ${XDG_SESSION_TYPE:-?} ${XDG_CURRENT_DESKTOP:-?}"
  command -v xrandr >/dev/null && xrandr --listmonitors
  echo; echo "== gpu"; lspci 2>/dev/null | grep -iE 'vga|3d|display'
  echo; echo "== packages"
  python3 -c 'import gi; gi.require_version("WebKit2","4.1"); from gi.repository import WebKit2; print("WebKitGTK", WebKit2.get_major_version(), WebKit2.get_minor_version(), WebKit2.get_micro_version())' 2>&1
  python3 -c 'import psutil; print("psutil", psutil.__version__)' 2>&1
  ls /usr/lib/*/gstreamer-1.0/ 2>/dev/null | grep -E 'libav|vaapi|va\.so' || echo "no gstreamer libav/vaapi found"
  echo; echo "== files"; ls -la "$DEST" "$DEST/wallpaper" 2>&1
  echo; echo "== running"; pgrep -af "^python3[^ ]* .*persona_desktop[.]py" || echo "not running"
} > "$out/info.txt" 2>&1
cp "$DEST"/install-log.txt "$DEST"/persona-desktop.log* "$out/" 2>/dev/null
if pgrep -f "^python3[^ ]* .*persona_desktop[.]py" >/dev/null; then
  timeout 10 "$DEST/app/persona_desktop.py" --diag "$out/wallpaper-diag.json" || echo "couldn't get the wallpaper diagnostics" >> "$out/info.txt"
fi
for f in "$out"/*; do sed -i "s|$HOME|~|g; s|\b$USER\b|USER|g" "$f"; done
(cd "$tmp" && python3 -m zipfile -c "$desk/PersonaDesktop-log.zip" PersonaDesktop-log)
rm -rf "$tmp"
echo "Made $desk/PersonaDesktop-log.zip. Send that along with what went wrong."
read -rp "Press Enter to close." _ || true

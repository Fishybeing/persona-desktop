#!/usr/bin/env bash
# Removes Persona Desktop. Your music is moved to ~/Music/Persona Desktop music first.
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/persona-desktop"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
echo "Uninstalling Persona Desktop..."
pkill -f "^python3[^ ]* .*persona_desktop[.]py" 2>/dev/null || true

music="$DEST/wallpaper/music"
keep="$HOME/Music/Persona Desktop music"
if [ -d "$music" ] && find "$music" -type f ! -name '*.txt' ! -name 'playlist.js' ! -name 'meta.json' ! -name 'likes.json' | grep -q .; then
  mkdir -p "$keep"
  find "$music" -mindepth 1 -maxdepth 1 ! -name 'PUT YOUR MUSIC HERE.txt' ! -name 'playlist.js' -exec mv -n -t "$keep" {} +
  echo "Your music is in $keep"
fi
[ -L "$HOME/Music/Persona Desktop" ] && rm "$HOME/Music/Persona Desktop"

icons=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("desktopIcons",""))' "$DEST/state.json" 2>/dev/null || true)
case "$icons" in
  mate:*) gsettings set org.mate.background show-desktop-icons "${icons#mate:}" && echo "Desktop icons are back." ;;
  nemo:*) gsettings set org.nemo.desktop desktop-layout "${icons#nemo:}" && echo "Desktop icons are back." ;;
esac

rm -f "$APPS"/persona-desktop*.desktop "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/persona-desktop.desktop"
rm -rf "$DEST" "${XDG_CACHE_HOME:-$HOME/.cache}/persona-desktop"
echo "Done. Your settings are still in ~/.config/persona-desktop; delete that folder too if you want."
read -rp "Press Enter to close." _ || true

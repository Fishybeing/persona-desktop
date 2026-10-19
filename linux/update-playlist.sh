#!/usr/bin/env bash
# Rescans the music folder, then reloads the wallpaper so the player picks up the new songs.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$here/update_playlist.py"
"$here/persona_desktop.py" --reload

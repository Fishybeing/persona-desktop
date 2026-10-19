#!/usr/bin/env bash
# Persona Desktop for Linux installer. Run it from the downloaded folder: ./install.sh
set -euo pipefail

VERSION="1.6.0-linux"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/persona-desktop"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/persona-desktop"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
MONORAIL_PAGE="https://moewalls.com/anime/yuki-x-aigis-in-the-train-persona-3-reload-live-wallpaper/"
STILL_URL="https://w.wallhaven.cc/full/k8/wallhaven-k8zd97.jpg"

red=$'\e[41;97m'; bold=$'\e[1;31m'; off=$'\e[0m'
step() { echo; echo "${bold}>> $*${off}"; }
info() { echo "   $*"; }

mkdir -p "$DEST" "$CONF"
exec > >(tee "$DEST/install-log.txt") 2>&1
trap 'echo; echo "${red}  SETUP FAILED  ${off}"; echo "   Line $LINENO: $BASH_COMMAND"; echo "   To get help, run ./linux/get-log.sh and send the zip it puts on your Desktop."' ERR

echo
echo "${red}  PERSONA DESKTOP  ${off}"
echo "  Animated Persona 3 wallpaper, music player and a Persona 5 app menu. Version $VERSION, installing from $SRC"

if [ "${XDG_SESSION_TYPE:-x11}" = "wayland" ]; then
  info "Warning: you're on a Wayland session. The wallpaper needs an X11 session (Xorg) to sit behind your windows."
  info "Log out, pick an 'Xorg' or 'X11' session on the login screen, and run this again."
fi

step "Checking what's needed"
need=()
python3 -c 'import gi; gi.require_version("Gtk","3.0"); gi.require_version("WebKit2","4.1"); from gi.repository import Gtk, WebKit2' 2>/dev/null || need+=(webkit)
python3 -c 'import psutil' 2>/dev/null || need+=(psutil)
gst-inspect-1.0 avdec_h264 >/dev/null 2>&1 || ls /usr/lib/*/gstreamer-1.0/libgstlibav.so >/dev/null 2>&1 || need+=(h264)
command -v curl >/dev/null || need+=(curl)
if [ ${#need[@]} -gt 0 ]; then
  if command -v apt-get >/dev/null; then
    declare -A pkg=([webkit]="python3-gi gir1.2-webkit2-4.1" [psutil]="python3-psutil" [h264]="gstreamer1.0-libav gstreamer1.0-plugins-good" [curl]="curl")
    cmd="sudo apt-get install -y"
  elif command -v dnf >/dev/null; then
    declare -A pkg=([webkit]="python3-gobject webkit2gtk4.1" [psutil]="python3-psutil" [h264]="gstreamer1-libav gstreamer1-plugins-good" [curl]="curl")
    cmd="sudo dnf install -y"
  elif command -v pacman >/dev/null; then
    declare -A pkg=([webkit]="python-gobject webkit2gtk-4.1" [psutil]="python-psutil" [h264]="gst-libav gst-plugins-good" [curl]="curl")
    cmd="sudo pacman -S --needed --noconfirm"
  else
    echo "Missing: ${need[*]}. Install WebKit2GTK 4.1 with Python GObject, python psutil, GStreamer libav and curl, then run this again."
    exit 1
  fi
  list=""; for n in "${need[@]}"; do list+=" ${pkg[$n]}"; done
  info "Installing:$list (it asks for your password)"
  $cmd $list
else
  info "Everything's already there."
fi

step "Setting up the wallpaper"
pkill -f "^python3[^ ]* .*persona_desktop[.]py" 2>/dev/null || true
mkdir -p "$DEST/wallpaper/music" "$DEST/app/res/menu" "$DEST/app/res/system"
for f in "$SRC"/wallpaper/*; do
  case "$(basename "$f")" in music|*.bat|*.ps1|LivelyInfo.json) ;; *) cp -r "$f" "$DEST/wallpaper/" ;; esac
done
cp "$SRC"/wallpaper/music/*.txt "$DEST/wallpaper/music/"
cp "$SRC"/linux/*.py "$SRC"/linux/*.sh "$DEST/app/"
cp -r "$SRC/linux/overlay" "$DEST/app/"
cp -r "$SRC/menu/PersonaMenu/@Resources/Fonts" "$SRC/menu/PersonaMenu/@Resources/Sounds" "$DEST/app/res/menu/"
cp "$SRC/skins/Persona 5 System"/*.png "$SRC/skins/Persona 5 System/@Resources/Fonts/Cartoonistkooky-p9za.otf" "$DEST/app/res/system/"
chmod +x "$DEST"/app/*.py "$DEST"/app/*.sh

if [ ! -s "$DEST/wallpaper/background.jpg" ]; then
  info "Downloading the monorail art by @Jurawings1 (Wallhaven)..."
  curl -sSfL -A "$UA" -o "$DEST/wallpaper/background.jpg" "$STILL_URL"
fi
video="$DEST/wallpaper/background.mp4"
if [ ! -f "$video" ] || [ "$(stat -c %s "$video")" -lt 1000000 ]; then
  info "Downloading the animated version from MoeWalls (about 60 MB)..."
  id=$(curl -sSfL -A "$UA" "$MONORAIL_PAGE" | grep -o 'id="moe-download"[^>]*data-url="[^"]*"' | sed 's/.*data-url="//; s/"$//' | head -n1 || true)
  [ -n "$id" ] || { echo "Couldn't find the video link on MoeWalls."; false; }
  curl -sSfL -A "$UA" -e "$MONORAIL_PAGE" -o "$video" "https://go.moewalls.com/download.php?video=$id"
fi
if command -v ffprobe >/dev/null && command -v ffmpeg >/dev/null; then
  h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$video" || echo 0)
  if [ "${h:-0}" -gt 1080 ]; then
    info "The video is ${h}p, shrinking it to 1080p so it plays smoothly (takes a minute)..."
    ffmpeg -v error -y -i "$video" -vf scale=-2:1080 -c:v libx264 -preset veryfast -crf 20 -an "$video.converting.mp4" && mv "$video.converting.mp4" "$video"
  fi
else
  info "ffmpeg isn't installed, so the video stays as it is (fine on most PCs)."
fi

mkdir -p "$HOME/Music"
[ -e "$HOME/Music/Persona Desktop" ] || ln -s "$DEST/wallpaper/music" "$HOME/Music/Persona Desktop"
python3 "$DEST/app/update_playlist.py" | head -n1 | sed 's/^/   /'

step "Setting up the Persona 5 menu and system bars"
pack=$(ls -t "$HOME"/Downloads/persona_5_desktop_icon_pack*.zip 2>/dev/null | head -n1 || true)
if [ -n "$pack" ]; then
  info "Found FrozenVayne's Persona 5 icon pack in Downloads, using it."
  python3 - "$pack" "$DEST/icons" <<'EOF'
import os, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
root = next(os.path.dirname(n) for n in z.namelist() if n.endswith("recycle_empty.ico"))
for n in z.namelist():
    if n.startswith(root + "/" if root else "") and not n.endswith("/"):
        out = os.path.join(sys.argv[2], os.path.relpath(n, root) if root else n)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "wb") as f:
            f.write(z.read(n))
EOF
elif [ ! -f "$DEST/icons/recycle_empty.ico" ]; then
  info "Optional: FrozenVayne's Persona 5 icon pack isn't in your Downloads, so the menu uses your normal app icons."
  info "Get it from https://www.deviantart.com/frozenvayne/art/Persona-5-Desktop-Icon-Pack-Version-1-0-747871613"
  info "then run install.sh again."
fi

state="$DEST/state.json"
if [ ! -f "$state" ]; then
  icons=""
  if gsettings get org.mate.background show-desktop-icons >/dev/null 2>&1; then
    icons="mate:$(gsettings get org.mate.background show-desktop-icons)"
  elif gsettings get org.nemo.desktop desktop-layout >/dev/null 2>&1; then
    icons="nemo:$(gsettings get org.nemo.desktop desktop-layout)"
  fi
  printf '{ "desktopIcons": "%s" }\n' "$icons" > "$state"
fi
if gsettings get org.mate.background show-desktop-icons >/dev/null 2>&1; then
  gsettings set org.mate.background show-desktop-icons false
  info "Turned off MATE's desktop icons so the wallpaper can be the desktop (uninstalling turns them back on)."
elif gsettings get org.nemo.desktop desktop-layout >/dev/null 2>&1; then
  gsettings set org.nemo.desktop desktop-layout "'false::false'"
  info "Turned off Cinnamon's desktop icons so the wallpaper can be the desktop (uninstalling turns them back on)."
fi

step "Adding app menu shortcuts"
mkdir -p "$APPS" "$AUTOSTART"
run="$DEST/app/persona_desktop.py"
entry() { # file, name, exec, icon
  cat > "$APPS/$1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Exec=$3
Icon=$4
Terminal=${5:-false}
Categories=Utility;
EOF
}
entry persona-desktop "Persona Desktop" "$run" preferences-desktop-wallpaper
entry persona-desktop-settings "Persona Desktop settings" "$run --settings" preferences-desktop
entry persona-desktop-playlist "Persona Desktop: update playlist" "\"$DEST/app/update-playlist.sh\"" view-refresh
entry persona-desktop-menu "Persona Desktop: update menu" "$run --update-menu" view-refresh
entry persona-desktop-music "Persona Desktop: music folder" "xdg-open \"$DEST/wallpaper/music\"" folder-music
entry persona-desktop-log "Persona Desktop: get log" "\"$DEST/app/get-log.sh\"" dialog-information true
entry persona-desktop-uninstall "Uninstall Persona Desktop" "\"$DEST/app/uninstall.sh\"" edit-delete true
cp "$APPS/persona-desktop.desktop" "$AUTOSTART/persona-desktop.desktop"
echo "X-GNOME-Autostart-enabled=true" >> "$AUTOSTART/persona-desktop.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true

step "Starting Persona Desktop"
nohup "$run" >/dev/null 2>&1 &
sleep 2

echo
echo "${red}  DONE  ${off}"
info "Put your music in: ~/Music/Persona Desktop"
info "Then open your app menu > Persona Desktop: update playlist."
info "Click the red MENU tab on your desktop to open your apps."
info "Wallpaper options (clock, Dark Hour, animation) are in Persona Desktop settings, or SETTINGS in the menu."
info "If something doesn't work: app menu > Persona Desktop: get log, and send the zip it makes."

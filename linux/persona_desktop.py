#!/usr/bin/env python3
"""Persona Desktop for Linux: shows the wallpaper page as the desktop, with the Persona 5 menu and system bars on top of it."""
import glob, json, os, re, sys, time, zipfile
# WebKit's sandboxed page process can hang on a stale shared cache (seen with ~/.cache/fontconfig), so this app
# and its page process get their own cache folder. Set before GLib reads it.
USER_CACHE = os.environ.get("XDG_CACHE_HOME")
os.environ["XDG_CACHE_HOME"] = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "cache")
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("WebKit2", "4.1")
gi.require_version("JavaScriptCore", "4.1")
from gi.repository import Gtk, Gdk, GLib, Gio, WebKit2
try:
    gi.require_foreign("cairo")
except ImportError:
    pass

APP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(APP)
WALL = os.path.join(ROOT, "wallpaper")
RES = os.path.join(APP, "res")
CONF = os.path.join(GLib.get_user_config_dir(), "persona-desktop")
LOG = os.path.join(ROOT, "persona-desktop.log")
APP_ID = "io.github.fishybeing.PersonaDesktop"

try:
    import psutil
except ImportError:
    psutil = None


def log(msg):
    sys.stderr.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
    sys.stderr.flush()


def read_json(path, default):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
    os.replace(tmp, path)


# ---------- settings (the same options Lively shows under Customize) ----------

PROPS = read_json(os.path.join(WALL, "LivelyProperties.json"), {})
SETTINGS_FILE = os.path.join(CONF, "settings.json")


def load_settings():
    s = {k: p.get("value") for k, p in PROPS.items() if p.get("type") != "button"}
    s.update({k: v for k, v in read_json(SETTINGS_FILE, {}).items() if k in s})
    return s


# ---------- the app list for the Persona 5 menu ----------

CAT_ORDER = ["GAMES", "SOCIAL", "INTERNET", "MEDIA", "CREATE", "OFFICE", "TOOLS"]
CAT_RULES = [
    ("SOCIAL", r"\bchat\b|discord|vesktop|teams|zoom|skype|whatsapp|telegram|slack|signal|messenger|guilded|teamspeak|mumble|element|hexchat|pidgin"),
    ("INTERNET", r"chrome|chromium|firefox|librewolf|edge|opera|brave|vivaldi|browser|epiphany|qbittorrent|transmission"),
    ("MEDIA", r"vlc|spotify|mpv|media player|rhythmbox|totem|celluloid|audacious|audacity|clementine|strawberry|lollypop|obs|netflix|youtube|plex|stremio|kodi|music|video player"),
    ("CREATE", r"gimp|krita|inkscape|blender|kdenlive|shotcut|openshot|davinci|resolve|darktable|godot|unity|unreal|aseprite|pinta|drawing|figma|ardour|lmms|musescore"),
    ("OFFICE", r"libreoffice|\bwriter\b|\bcalc\b|impress|onlyoffice|wps|document viewer|atril|evince|okular|obsidian|notion|thunderbird|evolution"),
    ("GAMES", r"steam|lutris|heroic|bottles|minecraft|prism ?launcher|modrinth|retroarch|dolphin emulator|rpcs3|pcsx2|yuzu|ryujinx|itch|roblox|sober"),
]
FD_CATS = [
    ("GAMES", {"Game"}),
    ("SOCIAL", {"InstantMessaging", "Chat", "IRCClient", "VideoConference", "Telephony"}),
    ("INTERNET", {"WebBrowser", "Network", "Email", "FileTransfer", "P2P"}),
    ("MEDIA", {"AudioVideo", "Audio", "Video", "Player", "Music", "TV"}),
    ("CREATE", {"Graphics", "2DGraphics", "3DGraphics", "VectorGraphics", "RasterGraphics", "Photography", "Development", "IDE", "AudioVideoEditing"}),
    ("OFFICE", {"Office", "WordProcessor", "Spreadsheet", "Presentation", "Viewer"}),
]
JUNK = re.compile(r"(?i)^(uninstall|remove)|help|manual|documentation|release notes|readme|about me|screensaver|log ?out|shut ?down|lock screen|switch user|power statistics|^disks$|disk usage|startup applications|software & updates|software updater|additional drivers|language support|input method|^fcitx|^ibus|personal file sharing|onboard|orca|^settings$|control center|^xterm$|^uxterm$|debian|^vim$|^nano$|persona desktop|^htop$|^btop|^dconf|^tweaks$|^avahi|^bluetooth|^hardinfo|^qt[ -v]|^nm-|network connections|printer|^gufw|^firewall|^timeshift|^synaptic|^gdebi|^java|^yelp|^gnome-|^mate-|steam linux runtime|proton|steamworks|^install steam$|character map|firmware updater|log file viewer|disk image mounter|font viewer|screen reader|^magnus$|search tool|color selection|midnight commander editor|^plank$|^xscreensaver")
# Persona 5 icons from FrozenVayne's pack: (shown name, icon file, is a game, matches app name, steam app id)
PACK = [
    ("Steam", "steam.ico", True, r"^Steam$", None),
    ("Battle.net", "battlenet_icon.ico", True, r"^Battle\.net$", None),
    ("EA app", "origin_icon.ico", True, r"^(Origin|EA|EA app)$", None),
    ("Ubisoft Connect", "uplay_icon.ico", True, r"^(Ubisoft Connect|Uplay)$", None),
    ("Counter-Strike 2", "Games/csgo_icon.ico", True, r"^Counter-Strike", 730),
    ("Fortnite", "Games/fortnite_icon.ico", True, r"^Fortnite$", None),
    ("Hearthstone", "Games/hearthstone_icon.ico", True, r"^Hearthstone$", None),
    ("League of Legends", "Games/lol_icon.ico", True, r"^League of Legends$", None),
    ("NieR:Automata", "Games/nier_icon.ico", True, r"^NieR", 524220),
    ("osu!", "Games/osu_icon.ico", True, r"^osu!", None),
    ("Overwatch", "Games/overwatch_icon.ico", True, r"^Overwatch", 2357570),
    ("PUBG: Battlegrounds", "Games/pubg_icon.ico", True, r"^PUBG", 578080),
    ("Rainbow Six Siege", "Games/r6siege_icon.ico", True, r"^Tom Clancy's Rainbow Six", 359550),
    ("Rocket League", "Games/rocket_league_icon.ico", True, r"^Rocket League", 252950),
    ("Team Fortress 2", "Games/tf2_icon.ico", True, r"^Team Fortress 2$", 440),
    ("Warframe", "Games/warframe_icon_KHv_icon.ico", True, r"^Warframe$", 230410),
    ("World of Warcraft", "Games/wow_icon.ico", True, r"^World of Warcraft", None),
    ("Google Chrome", "chrome_icon.ico", False, r"^Google Chrome$", None),
    ("Firefox", "firefox_icon.ico", False, r"^(Mozilla )?Firefox", None),
    ("Discord", "discord_icon.ico", False, r"^Discord$", None),
    ("Spotify", "spotify_icon.ico", False, r"^Spotify$", None),
    ("VLC media player", "music_icon.ico", False, r"^VLC media player$", None),
    ("Photoshop", "photoshop_icon.ico", False, r"^(Adobe )?Photoshop", None),
    ("Illustrator", "illustrator_icon.ico", False, r"^(Adobe )?Illustrator", None),
    ("Files", "file_explorer.ico", False, r"^(Files|Caja|Nautilus|Nemo|Thunar|Dolphin|PCManFM.*)$", None),
    ("Terminal", "command_prompt_icon.ico", False, r"^(MATE )?Terminal$|^Konsole$|^Tilix$|^Alacritty$|^kitty$", None),
]


def category(name, exe, fd_cats, is_game):
    if is_game:
        return "GAMES"
    s = (name + " " + exe).lower()
    for cat, rx in CAT_RULES:
        if re.search(rx, s):
            return cat
    for cat, names in FD_CATS:
        if names & fd_cats:
            return cat
    return "TOOLS"


def steam_roots():
    home = os.path.expanduser("~")
    roots = []
    for d in (".steam/steam", ".local/share/Steam", ".var/app/com.valvesoftware.Steam/.local/share/Steam"):
        p = os.path.realpath(os.path.join(home, d))
        if os.path.isdir(os.path.join(p, "steamapps")) and p not in roots:
            roots.append(p)
    return roots


def steam_games():
    """Installed Steam games as {appid: name}, from every Steam library folder."""
    games = {}
    for root in steam_roots():
        libs = [root]
        try:
            with open(os.path.join(root, "steamapps", "libraryfolders.vdf"), encoding="utf-8", errors="replace") as f:
                libs += re.findall(r'"path"\s+"([^"]+)"', f.read())
        except OSError:
            pass
        for lib in dict.fromkeys(libs):
            for acf in glob.glob(os.path.join(lib, "steamapps", "appmanifest_*.acf")):
                try:
                    with open(acf, encoding="utf-8", errors="replace") as f:
                        txt = f.read()
                except OSError:
                    continue
                m_id, m_name = re.search(r'"appid"\s+"(\d+)"', txt), re.search(r'"name"\s+"([^"]+)"', txt)
                if m_id and m_name and not JUNK.search(m_name.group(1)):
                    games[m_id.group(1)] = m_name.group(1)
    return games


def file_url(path):
    return GLib.filename_to_uri(path, None)


def icon_url(gicon):
    if gicon is None:
        return ""
    if isinstance(gicon, Gio.FileIcon):
        p = gicon.get_file().get_path()
        return file_url(p) if p and os.path.exists(p) else ""
    info = Gtk.IconTheme.get_default().lookup_by_gicon(gicon, 64, Gtk.IconLookupFlags.FORCE_SIZE)
    return file_url(info.get_filename()) if info and info.get_filename() else ""


def image_url(path):
    path = os.path.expanduser(path)
    return file_url(path) if path and os.path.isfile(path) and re.search(r"(?i)\.(png|ico|svg|jpe?g|webp)$", path) else ""


def build_menu():
    """Returns (sections for the page, {id: how to launch it})."""
    cfg = {"personaIconsOnlyInGames": False, "alwaysShowGames": [], "hideSections": [], "iconOverrides": {}}
    cfg.update(read_json(os.path.join(CONF, "menu-settings.json"), {}))
    hide = {str(s).upper() for s in cfg.get("hideSections") or []}
    pack_dir = os.path.join(ROOT, "icons")
    items, launch, seen = [], {}, set()

    def add(name, target, cat, icon, persona):
        if name.lower() in seen:
            return
        seen.add(name.lower())
        iid = "i%d" % len(items)
        launch[iid] = target
        items.append({"id": iid, "name": name, "cat": cat, "icon": icon, "persona": persona})

    apps = [a for a in Gio.AppInfo.get_all() if isinstance(a, Gio.DesktopAppInfo) and a.should_show()]
    games = steam_games()
    for name, ico, is_game, rx, appid in PACK:
        target, shown = None, name
        if appid and str(appid) in games:
            target = "steam://rungameid/%d" % appid
        if not target:
            hit = next((a for a in apps if re.search(rx, a.get_name() or "")), None)
            if hit:
                target, shown = hit, hit.get_name()
        if not target:
            continue
        icon = image_url(os.path.join(pack_dir, ico))
        persona = bool(icon)
        if not icon and isinstance(target, Gio.AppInfo):
            icon = icon_url(target.get_icon())
        add(shown, target, category(shown, "", set(), is_game), icon, persona)

    steam_icon = next((icon_url(a.get_icon()) for a in apps if (a.get_name() or "") == "Steam"), "")
    for a in apps:
        name = a.get_name() or ""
        exe = a.get_executable() or ""
        if not name or JUNK.search(name) or re.search(r"(?i)--uninstall", a.get_commandline() or ""):
            continue
        cats = set(filter(None, (a.get_categories() or "").split(";")))
        if cats & {"Settings", "DesktopSettings", "HardwareSettings", "PackageManager", "Screensaver"}:
            continue
        game = "Game" in cats or "steam://rungameid/" in (a.get_commandline() or "")
        if game:
            m = re.search(r"steam://rungameid/(\d+)", a.get_commandline() or "")
            if m:
                games.pop(m.group(1), None)
        add(name, a, category(name, os.path.basename(exe), cats, game), icon_url(a.get_icon()), False)
    for appid, name in sorted(games.items(), key=lambda g: g[1].lower()):
        icon = ""
        for root in steam_roots():
            hits = glob.glob(os.path.join(root, "appcache", "librarycache", appid, "*.jpg"))
            small = [h for h in hits if re.match(r"^[0-9a-f]{40}\.jpg$", os.path.basename(h))]
            if small:
                icon = file_url(small[0])
                break
        add(name, "steam://rungameid/" + appid, "GAMES", icon or steam_icon, False)

    for it in items:
        for k, path in (cfg.get("iconOverrides") or {}).items():
            if it["name"].lower().startswith(str(k).lower()):
                url = image_url(str(path))
                if url:
                    it["icon"], it["persona"] = url, True
                break

    sections = []
    keep = [str(g).lower() for g in cfg.get("alwaysShowGames") or []]
    for c in CAT_ORDER:
        if c in hide:
            continue
        lst = sorted((i for i in items if i["cat"] == c), key=lambda i: i["name"].lower())
        if c == "GAMES" and cfg.get("personaIconsOnlyInGames"):
            lst = [i for i in lst if i["persona"] or any(i["name"].lower().startswith(k) for k in keep)]
        if lst:
            sections.append({"title": c, "items": [{"id": i["id"], "name": i["name"], "icon": i["icon"]} for i in lst]})
    return sections, launch


# ---------- windows ----------

class SettingsWindow(Gtk.Window):
    def __init__(self, app):
        super().__init__(title="Persona Desktop settings")
        self.app = app
        self.set_default_size(460, -1)
        self.set_border_width(16)
        self.set_icon_name("preferences-desktop-wallpaper")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(box)
        s = load_settings()
        buttons = Gtk.Box(spacing=8)
        for key, p in PROPS.items():
            t = p.get("type")
            if t == "checkbox":
                w = Gtk.CheckButton(label=p["text"])
                w.set_active(bool(s.get(key)))
                w.connect("toggled", lambda w, k=key: self.changed(k, w.get_active()))
                box.pack_start(w, False, False, 0)
            elif t == "slider":
                box.pack_start(Gtk.Label(label=p["text"], xalign=0, wrap=True, max_width_chars=50), False, False, 0)
                w = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, p.get("min", 0), p.get("max", 100), p.get("step", 1))
                w.set_value(float(s.get(key) or 0))
                w.set_digits(0)
                w.connect("value-changed", lambda w, k=key: self.changed(k, int(w.get_value())))
                box.pack_start(w, False, False, 0)
            elif t == "dropdown":
                row = Gtk.Box(spacing=10)
                row.pack_start(Gtk.Label(label=p["text"]), False, False, 0)
                w = Gtk.ComboBoxText()
                for item in p.get("items", []):
                    w.append_text(item)
                w.set_active(int(s.get(key) or 0))
                w.connect("changed", lambda w, k=key: self.changed(k, w.get_active()))
                row.pack_start(w, True, True, 0)
                box.pack_start(row, False, False, 0)
            elif t == "button":
                w = Gtk.Button(label=p.get("value", key))
                w.connect("clicked", lambda w, k=key: self.app.wallpaper.prop(k, True))
                buttons.pack_start(w, True, True, 0)
        box.pack_start(Gtk.Label(label="Music", xalign=0), False, False, 4)
        box.pack_start(buttons, False, False, 0)
        tools = Gtk.Box(spacing=8)
        for label, fn in (("Update playlist", self.app.update_playlist), ("Update menu", self.app.update_menu), ("Open music folder", self.app.open_music)):
            b = Gtk.Button(label=label)
            b.connect("clicked", lambda b, fn=fn: fn())
            tools.pack_start(b, True, True, 0)
        box.pack_start(tools, False, False, 8)

    def changed(self, key, val):
        s = read_json(SETTINGS_FILE, {})
        s[key] = val
        write_json(SETTINGS_FILE, s)
        self.app.wallpaper.prop(key, val)


class Wallpaper(Gtk.Window):
    """The animated wallpaper page as the desktop, with the menu and system bars drawn inside the same page."""

    def __init__(self, app, monitor):
        super().__init__(title="Persona Desktop")
        self.app = app
        self.ready = False
        self.set_type_hint(Gdk.WindowTypeHint.DESKTOP)
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_below(True)
        self.stick()
        self.place(monitor)

        data = os.path.join(GLib.get_user_data_dir(), "persona-desktop", "webdata")
        manager = WebKit2.WebsiteDataManager(base_data_directory=data, base_cache_directory=os.path.join(GLib.get_user_cache_dir(), "webkit"))
        ctx = WebKit2.WebContext.new_with_website_data_manager(manager)
        ctx.set_cache_model(WebKit2.CacheModel.DOCUMENT_VIEWER)
        ucm = WebKit2.UserContentManager()
        ucm.register_script_message_handler("pd")
        ucm.connect("script-message-received::pd", self.on_message)
        css = open(os.path.join(APP, "overlay", "overlay.css"), encoding="utf-8").read().replace("{RES}", file_url(RES))
        js = open(os.path.join(APP, "overlay", "overlay.js"), encoding="utf-8").read().replace('"{RES}"', json.dumps(file_url(RES))).replace('"{CSS}"', json.dumps(css))
        ucm.add_script(WebKit2.UserScript(js, WebKit2.UserContentInjectedFrames.TOP_FRAME, WebKit2.UserScriptInjectionTime.END, None, None))
        self.view = WebKit2.WebView(web_context=ctx, user_content_manager=ucm)
        st = self.view.get_settings()
        st.set_allow_file_access_from_file_urls(True)
        st.set_allow_universal_access_from_file_urls(True)
        st.set_media_playback_requires_user_gesture(False)
        st.set_enable_webaudio(True)
        st.set_enable_write_console_messages_to_stdout(True)
        st.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.NEVER if os.environ.get("PD_NOGPU") else WebKit2.HardwareAccelerationPolicy.ALWAYS)
        self.view.set_background_color(Gdk.RGBA(0.02, 0.09, 0.21, 1))
        self.view.connect("load-changed", self.on_load)
        self.view.connect("context-menu", lambda *a: True)
        self.view.connect("web-process-terminated", self.on_crash)
        self.view.connect("decide-policy", self.on_policy)
        self.add(self.view)
        self.load()

    def place(self, monitor):
        g = monitor.get_geometry()
        w = monitor.get_workarea()
        self.geo, self.work = g, w
        self.move(g.x, g.y)
        self.set_default_size(g.width, g.height)
        self.resize(g.width, g.height)

    def load(self):
        self.ready = False
        self.view.load_uri(file_url(os.path.join(WALL, "index.html")))

    def js(self, code, done=None):
        def finish(view, res, *_):
            try:
                v = view.evaluate_javascript_finish(res)
                if done:
                    done(v.to_string() if v else None)
            except GLib.Error as e:
                log("javascript failed: " + e.message)
                if done:
                    done(None)
        self.view.evaluate_javascript(code, -1, None, None, None, finish, None)

    def prop(self, name, val):
        if self.ready:
            self.js("window.livelyPropertyListener && livelyPropertyListener(%s, %s)" % (json.dumps(name), json.dumps(val)))

    def on_load(self, view, event):
        if event != WebKit2.LoadEvent.FINISHED:
            return
        self.ready = True
        for k, v in load_settings().items():
            self.prop(k, v)
        w = self.work
        self.js("PD.setWorkArea(%d, %d, %d, %d)" % (w.x - self.geo.x, w.y - self.geo.y, w.width, w.height))
        self.app.push_menu()
        log("wallpaper loaded")

    def on_crash(self, view, reason):
        log("web process ended (%s), reloading in 3 seconds" % reason)
        GLib.timeout_add_seconds(3, lambda: (self.load(), False)[1])

    def on_policy(self, view, decision, kind):
        if kind == WebKit2.PolicyDecisionType.NAVIGATION_ACTION:
            uri = decision.get_navigation_action().get_request().get_uri()
            if not uri.startswith("file:") and not uri.startswith("about:"):
                decision.ignore()
                self.app.open_uri(uri)
                return True
        return False

    def on_message(self, ucm, result):
        try:
            msg = json.loads(result.get_js_value().to_string())
        except (ValueError, AttributeError):
            return
        cmd = msg.get("cmd")
        if cmd == "launch":
            self.app.launch(msg.get("id"))
        elif cmd == "updateMenu":
            self.app.update_menu()
        elif cmd == "settings":
            self.app.open_settings()


class Still(Gtk.Window):
    """Extra monitors just get the still picture."""

    def __init__(self, monitor):
        super().__init__()
        self.set_type_hint(Gdk.WindowTypeHint.DESKTOP)
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_keep_below(True)
        self.stick()
        g = monitor.get_geometry()
        self.move(g.x, g.y)
        self.resize(g.width, g.height)
        view = WebKit2.WebView()
        view.load_html('<body style="margin:0;background:#061636 url(\'%s\') center 40%%/cover no-repeat"></body>' % file_url(os.path.join(WALL, "background.jpg")), "file:///")
        self.add(view)


class PersonaDesktop(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.wallpaper = None
        self.others = []
        self.launchers = {}
        self.settings_win = None
        for name, desc in (("reload", "Reload the wallpaper (after Update playlist)"), ("update-menu", "Rebuild the app list in the menu"),
                           ("settings", "Open the settings"), ("play-pause", "Play or pause the music"), ("next", "Next song"),
                           ("prev", "Previous song"), ("quit", "Close Persona Desktop")):
            self.add_main_option(name, 0, GLib.OptionFlags.NONE, GLib.OptionArg.NONE, desc, None)
        self.add_main_option("js", 0, GLib.OptionFlags.HIDDEN, GLib.OptionArg.STRING, "Run JavaScript in the wallpaper page", "CODE")
        self.add_main_option("diag", 0, GLib.OptionFlags.NONE, GLib.OptionArg.FILENAME, "Save the wallpaper's diagnostics to a file", "FILE")

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.hold()
        display = Gdk.Display.get_default()
        self.build_windows(display)
        screen = Gdk.Screen.get_default()
        screen.connect("monitors-changed", lambda s: self.build_windows(display))
        if psutil:
            psutil.cpu_percent(None)
            GLib.timeout_add(1000, self.push_stats)

    def build_windows(self, display):
        primary = display.get_primary_monitor() or display.get_monitor(0)
        if self.wallpaper:
            self.wallpaper.place(primary)
        else:
            self.wallpaper = Wallpaper(self, primary)
            self.wallpaper.show_all()
        for w in self.others:
            w.destroy()
        self.others = []
        for i in range(display.get_n_monitors()):
            m = display.get_monitor(i)
            if m != primary:
                s = Still(m)
                s.show_all()
                self.others.append(s)

    def do_command_line(self, cmdline):
        opts = cmdline.get_options_dict().end().unpack()
        if opts.get("quit"):
            self.quit()
        elif opts.get("reload"):
            self.wallpaper.load()
        elif opts.get("update-menu"):
            self.update_menu()
        elif opts.get("settings"):
            self.open_settings()
        elif opts.get("js"):
            self.wallpaper.js(opts["js"])
        elif opts.get("diag"):
            path = opts["diag"]
            if not isinstance(path, str):
                path = bytes(path).rstrip(b"\0").decode()
            hold = [cmdline]

            def save(text):
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text or "{}")
                hold.clear()
            self.wallpaper.js("JSON.stringify(window.__pdDiag ? window.__pdDiag() : {}, null, 2)", save)
        else:
            for flag, cmd in (("play-pause", "playPause"), ("next", "nextTrack"), ("prev", "prevTrack")):
                if opts.get(flag):
                    self.wallpaper.prop(cmd, True)
        return 0

    def push_menu(self):
        if not self.launchers:
            sections, self.launchers = build_menu()
            self.menu_sections = sections
        if self.wallpaper and self.wallpaper.ready:
            self.wallpaper.js("PD.setMenu(%s)" % json.dumps(self.menu_sections))

    def update_menu(self):
        self.launchers = {}
        self.push_menu()
        n = sum(len(s["items"]) for s in self.menu_sections)
        log("menu built: %d apps" % n)

    def launch(self, iid):
        self.start(self.launchers.get(iid))

    def start(self, target):
        """Opens an app or a link with the user's own cache folder, not the wallpaper's."""
        ctx = Gdk.Display.get_default().get_app_launch_context()
        if USER_CACHE:
            ctx.setenv("XDG_CACHE_HOME", USER_CACHE)
        else:
            ctx.unsetenv("XDG_CACHE_HOME")
        try:
            if isinstance(target, Gio.AppInfo):
                target.launch([], ctx)
            elif isinstance(target, str):
                Gio.AppInfo.launch_default_for_uri(target, ctx)
        except GLib.Error as e:
            log("couldn't open %s: %s" % (target, e.message))

    def push_stats(self):
        if self.wallpaper and self.wallpaper.ready:
            self.wallpaper.js("PD.setStats(%d, %d)" % (round(psutil.cpu_percent(None)), round(psutil.virtual_memory().percent)))
        return True

    def open_settings(self):
        if not self.settings_win:
            self.settings_win = SettingsWindow(self)
            self.settings_win.connect("destroy", lambda w: setattr(self, "settings_win", None))
        self.settings_win.show_all()
        self.settings_win.present()

    def update_playlist(self):
        import subprocess
        subprocess.run([sys.executable, os.path.join(APP, "update_playlist.py")])
        self.wallpaper.load()

    def open_uri(self, uri):
        self.start(uri)

    def open_music(self):
        self.open_uri(file_url(os.path.realpath(os.path.join(WALL, "music"))))


def running():
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        r = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
                          GLib.Variant("(s)", (APP_ID,)), GLib.VariantType("(b)"), Gio.DBusCallFlags.NONE, 2000, None)
        return r.unpack()[0]
    except GLib.Error:
        return False


def main():
    if any(a == "--quit" or a.startswith(("--diag", "--js")) for a in sys.argv[1:]) and not running():
        return 0
    if not sys.stderr.isatty():
        try:
            if os.path.getsize(LOG) > 2_000_000:
                os.replace(LOG, LOG + ".old")
        except OSError:
            pass
        fd = os.open(LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
        os.dup2(fd, 1)
        os.dup2(fd, 2)
    return PersonaDesktop().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())

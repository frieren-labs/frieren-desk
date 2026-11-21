#!/usr/bin/env python3
"""Frieren tray icon: StatusNotifierItem + DBusMenu.

Registers a real system tray icon with the StatusNotifierWatcher (the DMS bar
hosts it) and exposes a menu that controls the Frieren Quickshell instance over
its IPC:

    qs -c frieren ipc call frieren <method> [args]

The helper exits with the shell: it asks the kernel for a parent death signal, so
a crash or restart does not leave an orphan icon behind. State changes are
watched with Gio file monitoring, with a cheap mtime poll as a fallback.

Requires: python-dbus, python-gobject.
"""

from __future__ import annotations

import ctypes
import json
import os
import shutil
import signal
import subprocess
import sys

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import Gio, GLib

SNI_PATH = "/StatusNotifierItem"
MENU_PATH = "/MenuBar"
BUS_NAME = "org.kde.StatusNotifierItem-frieren"
CONFIG_NAME = "frieren"

# Menu ids. They only need to be stable inside this helper.
ID_TOGGLE_PET = 1
ID_CHAT = 2
ID_FRESH = 3
ID_STOP = 4
ID_SEP_1 = 5
ID_SETTINGS = 6
ID_WANDER = 7
ID_SLEEP = 8
ID_BLINK = 9
ID_SIZE = 10
ID_SMALL = 11
ID_MEDIUM = 12
ID_LARGE = 13
ID_RESET = 14
ID_SEP_2 = 15
ID_QUIT = 16
ID_AUTH = 17

DEFAULTS = {
    "minimized": False,
    "wander": True,
    "sleep": True,
    "blink": True,
    "scale": 1.0,
    "auth": False,
    "busy": False,
    "chatOpen": False,
}


def set_parent_death_signal() -> None:
    """Terminate with the qs process instead of polling its IPC."""
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        PR_SET_PDEATHSIG = 1
        libc.prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
        if os.getppid() == 1:
            raise SystemExit(0)
    except OSError:
        pass


def read_bytes(path: str) -> bytes:
    try:
        with open(path, "rb") as handle:
            return handle.read()
    except OSError:
        return b""


def read_state(path: str) -> dict:
    raw = {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, ValueError):
        raw = {}

    state = dict(DEFAULTS)
    state["minimized"] = bool(raw.get("minimized", False))
    state["wander"] = bool(raw.get("wander", True))
    state["sleep"] = bool(raw.get("sleep", True))
    state["blink"] = bool(raw.get("blink", True))
    state["auth"] = bool(raw.get("auth", False))
    state["busy"] = bool(raw.get("busy", False))
    state["chatOpen"] = bool(raw.get("chatOpen", False))
    try:
        state["scale"] = float(raw.get("scale", 1.0))
    except (TypeError, ValueError):
        state["scale"] = 1.0
    return state


def pixmap(size: int, data: bytes) -> dbus.Struct:
    return dbus.Struct(
        (dbus.Int32(size), dbus.Int32(size), dbus.ByteArray(data)),
        signature="iiay",
    )


def props() -> dbus.Dictionary:
    return dbus.Dictionary({}, signature="sv")


class FrierenMenu(dbus.service.Object):
    """com.canonical.dbusmenu implementation for the tray icon."""

    def __init__(self, bus_name: dbus.service.BusName, item: "FrierenItem") -> None:
        self.item = item
        super().__init__(bus_name, MENU_PATH)

    # ---------------- menu construction ----------------
    @staticmethod
    def _entry(
        label: str | None = None,
        *,
        enabled: bool = True,
        kind: str = "standard",
        children_display: str | None = None,
        toggle_type: str | None = None,
        toggle_state: int | None = None,
    ) -> dbus.Dictionary:
        entry = props()
        if label is not None:
            entry["label"] = dbus.String(label)
        entry["enabled"] = dbus.Boolean(enabled)
        entry["visible"] = dbus.Boolean(True)
        entry["type"] = dbus.String(kind)
        if children_display:
            entry["children-display"] = dbus.String(children_display)
        if toggle_type:
            entry["toggle-type"] = dbus.String(toggle_type)
        if toggle_state is not None:
            entry["toggle-state"] = dbus.Int32(toggle_state)
        return entry

    def _tree(self) -> dict[int, tuple[dbus.Dictionary, list[int]]]:
        state = read_state(self.item.state_path)
        scale = state["scale"]

        small = scale <= 0.92
        large = scale >= 1.08
        medium = not small and not large

        tree: dict[int, tuple[dbus.Dictionary, list[int]]] = {}

        def add(node_id: int, entry: dbus.Dictionary, children: list[int] | None = None) -> None:
            tree[node_id] = (entry, children or [])

        add(ID_TOGGLE_PET, self._entry("Show pet" if state["minimized"] else "Hide pet"))
        add(ID_CHAT, self._entry("Close chat" if state["chatOpen"] else "Open chat"))
        add(ID_FRESH, self._entry("New conversation"))
        add(ID_STOP, self._entry("Stop", enabled=state["busy"]))
        add(ID_SEP_1, self._entry(kind="separator"))
        add(ID_AUTH, self._entry(
            "Account..." if state["auth"] else "Setup account..."))
        add(ID_SETTINGS, self._entry("Settings", kind="submenu", children_display="submenu"),
            [ID_WANDER, ID_SLEEP, ID_BLINK, ID_SIZE, ID_RESET])
        add(ID_WANDER, self._entry("Wander", toggle_type="checkmark",
                                   toggle_state=1 if state["wander"] else 0))
        add(ID_SLEEP, self._entry("Sleep when idle", toggle_type="checkmark",
                                  toggle_state=1 if state["sleep"] else 0))
        add(ID_BLINK, self._entry("Blink", toggle_type="checkmark",
                                  toggle_state=1 if state["blink"] else 0))
        add(ID_SIZE, self._entry("Size", kind="submenu", children_display="submenu"),
            [ID_SMALL, ID_MEDIUM, ID_LARGE])
        add(ID_SMALL, self._entry("Small", toggle_type="radio", toggle_state=1 if small else 0))
        add(ID_MEDIUM, self._entry("Medium", toggle_type="radio", toggle_state=1 if medium else 0))
        add(ID_LARGE, self._entry("Large", toggle_type="radio", toggle_state=1 if large else 0))
        add(ID_RESET, self._entry("Reset position"))
        add(ID_SEP_2, self._entry(kind="separator"))
        add(ID_QUIT, self._entry("Quit"))
        return tree

    def _node(self, node_id: int, tree: dict[int, tuple[dbus.Dictionary, list[int]]]) -> dbus.Struct:
        entry, children = tree[node_id]
        child_nodes = dbus.Array(
            [self._node(child, tree) for child in children],
            signature="v",
        )
        return dbus.Struct(
            (dbus.Int32(node_id), entry, child_nodes),
            signature="ia{sv}av",
        )

    def _revision(self) -> int:
        try:
            return int(os.path.getmtime(self.item.state_path) * 1000) & 0xFFFFFFFF
        except OSError:
            return 1

    def notify_state(self) -> None:
        """Tell the tray client that labels and checks changed."""
        tree = self._tree()
        revision = self._revision()
        self.LayoutUpdated(dbus.UInt32(revision), dbus.Int32(0))

        updated = []
        for node_id in (
            ID_TOGGLE_PET, ID_CHAT, ID_STOP,
            ID_WANDER, ID_SLEEP, ID_BLINK,
            ID_SMALL, ID_MEDIUM, ID_LARGE,
            ID_AUTH,
        ):
            if node_id in tree:
                updated.append(dbus.Struct(
                    (dbus.Int32(node_id), tree[node_id][0]),
                    signature="ia{sv}",
                ))
        self.ItemsPropertiesUpdated(
            dbus.Array(updated, signature="(ia{sv})"),
            dbus.Array([], signature="(ias)"),
        )

    # ---------------- com.canonical.dbusmenu ----------------
    @dbus.service.method("com.canonical.dbusmenu", in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parent_id, recursion_depth, property_names):
        tree = self._tree()
        parent = int(parent_id)
        if parent == 0:
            root = dbus.Dictionary({
                "type": dbus.String("submenu"),
                "children-display": dbus.String("submenu"),
            }, signature="sv")
            layout = dbus.Struct((
                dbus.Int32(0),
                root,
                dbus.Array([self._node(child, tree) for child in
                            [ID_TOGGLE_PET, ID_CHAT, ID_FRESH, ID_STOP, ID_SEP_1,
                             ID_AUTH, ID_SETTINGS, ID_SEP_2, ID_QUIT]], signature="v"),
            ), signature="ia{sv}av")
        elif parent in tree:
            layout = self._node(parent, tree)
        else:
            layout = dbus.Struct((
                dbus.Int32(parent),
                props(),
                dbus.Array([], signature="v"),
            ), signature="ia{sv}av")
        return dbus.UInt32(self._revision()), layout

    @dbus.service.method("com.canonical.dbusmenu", in_signature="aias", out_signature="a(ia{sv})")
    def GetGroupProperties(self, ids, property_names):
        tree = self._tree()
        result = []
        for node_id in ids:
            node = int(node_id)
            if node in tree:
                result.append(dbus.Struct(
                    (dbus.Int32(node), tree[node][0]),
                    signature="ia{sv}",
                ))
        return dbus.Array(result, signature="(ia{sv})")

    @dbus.service.method("com.canonical.dbusmenu", in_signature="is", out_signature="v")
    def GetProperty(self, node_id, name):
        tree = self._tree()
        node = int(node_id)
        if node in tree:
            return tree[node][0].get(name, dbus.String(""))
        return dbus.String("")

    @dbus.service.method("com.canonical.dbusmenu", in_signature="isvu", out_signature="")
    def Event(self, node_id, event_id, data, timestamp):
        if str(event_id) == "clicked":
            self._activate(int(node_id))

    @dbus.service.method("com.canonical.dbusmenu", in_signature="i", out_signature="b")
    def AboutToShow(self, node_id):
        return False

    @dbus.service.method("com.canonical.dbusmenu", in_signature="ai", out_signature="aiai")
    def AboutToShowGroup(self, ids):
        return dbus.Array([], signature="i"), dbus.Array([], signature="i")

    @dbus.service.signal("com.canonical.dbusmenu", signature="ui")
    def LayoutUpdated(self, revision, parent):
        pass

    @dbus.service.signal("com.canonical.dbusmenu", signature="a(ia{sv})a(ias)")
    def ItemsPropertiesUpdated(self, updated, removed):
        pass

    # ---------------- org.freedesktop.DBus.Properties ----------------
    @staticmethod
    def _properties() -> dict:
        return {
            "Version": dbus.UInt32(3),
            "TextDirection": dbus.String("ltr"),
            "Status": dbus.String("normal"),
            "IconThemePath": dbus.Array([], signature="s"),
        }

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self._properties().get(name, dbus.String(""))

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return dbus.Dictionary(self._properties(), signature="sv")

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv", out_signature="")
    def Set(self, interface, name, value):
        pass

    @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    # ---------------- actions ----------------
    def _activate(self, node_id: int) -> None:
        state = read_state(self.item.state_path)
        if node_id == ID_TOGGLE_PET:
            self.item.call("restore" if state["minimized"] else "minimize")
        elif node_id == ID_CHAT:
            self.item.call("toggle")
        elif node_id == ID_FRESH:
            self.item.call("fresh")
        elif node_id == ID_STOP:
            self.item.call("stop")
        elif node_id == ID_WANDER:
            self.item.call("wander", "toggle")
        elif node_id == ID_SLEEP:
            self.item.call("sleep", "toggle")
        elif node_id == ID_BLINK:
            self.item.call("blink", "toggle")
        elif node_id == ID_SMALL:
            self.item.call("scale", "0.85")
        elif node_id == ID_MEDIUM:
            self.item.call("scale", "1.0")
        elif node_id == ID_LARGE:
            self.item.call("scale", "1.15")
        elif node_id == ID_RESET:
            self.item.call("resetpos")
        elif node_id == ID_AUTH:
            self.item.call("auth")
        elif node_id == ID_QUIT:
            self.item.call("quit")


class FrierenItem(dbus.service.Object):
    """org.kde.StatusNotifierItem implementation."""

    def __init__(
        self,
        connection: dbus.Bus,
        bus_name: dbus.service.BusName,
        icon_png: str,
        argb_paths: dict[int, str],
        state_path: str,
        loop: GLib.MainLoop,
    ) -> None:
        self.bus_connection = connection
        self.service = connection.get_unique_name()
        self.icon_png = icon_png
        self.argb = {size: read_bytes(path) for size, path in argb_paths.items()}
        self.state_path = state_path
        self.loop = loop
        self.qs = shutil.which("qs") or "/usr/bin/qs"
        self.last_state_mtime = 0
        self.state_monitor = None
        super().__init__(bus_name, SNI_PATH)
        self.menu = FrierenMenu(bus_name, self)

        GLib.timeout_add_seconds(1, self._register)
        GLib.timeout_add_seconds(30, self._reregister)
        self._watch_state_file()

    # ---------------- properties ----------------
    def _props(self) -> dict:
        pixels = dbus.Array(
            [pixmap(size, data) for size, data in sorted(self.argb.items(), reverse=True) if data],
            signature="(iiay)",
        )
        empty_pixels = dbus.Array([], signature="(iiay)")
        return {
            "Category": dbus.String("ApplicationStatus"),
            "Id": dbus.String("frieren"),
            "Title": dbus.String("Frieren"),
            "Status": dbus.String("Active"),
            "WindowId": dbus.Int32(0),
            "IconName": dbus.String(self.icon_png),
            "IconPixmap": pixels,
            "OverlayIconName": dbus.String(""),
            "OverlayIconPixmap": empty_pixels,
            "AttentionIconName": dbus.String(""),
            "AttentionIconPixmap": empty_pixels,
            "AttentionMovieName": dbus.String(""),
            "ToolTip": dbus.Struct((
                dbus.String(""),
                empty_pixels,
                dbus.String("Frieren"),
                dbus.String("Desktop assistant"),
            ), signature="sa(iiay)ss"),
            "ItemIsMenu": dbus.Boolean(True),
            "Menu": dbus.ObjectPath(MENU_PATH),
        }

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self._props().get(name, dbus.String(""))

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return dbus.Dictionary(self._props(), signature="sv")

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv", out_signature="")
    def Set(self, interface, name, value):
        pass

    @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    # ---------------- StatusNotifierItem methods ----------------
    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii", out_signature="")
    def Activate(self, x, y):
        self.call("toggle")

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii", out_signature="")
    def ContextMenu(self, x, y):
        pass

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii", out_signature="")
    def SecondaryActivate(self, x, y):
        pass

    @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ib", out_signature="")
    def Scroll(self, delta, horizontal):
        pass

    # ---------------- helpers ----------------
    def _state_mtime(self) -> int:
        try:
            return int(os.path.getmtime(self.state_path) * 1000)
        except OSError:
            return 0

    def _refresh_state(self) -> None:
        mtime = self._state_mtime()
        if mtime != self.last_state_mtime:
            self.last_state_mtime = mtime
            self.menu.notify_state()

    def _watch_state(self) -> bool:
        self._refresh_state()
        return True

    def _state_changed(self, monitor, file, other_file, event_type) -> None:
        self._refresh_state()

    def _watch_state_file(self) -> None:
        # monitor_file also reports creation, but the parent directory must
        # exist. The shell creates it on the first save.
        state_dir = os.path.dirname(self.state_path)
        if state_dir:
            try:
                os.makedirs(state_dir, exist_ok=True)
            except OSError:
                pass
        try:
            monitor = Gio.File.new_for_path(self.state_path).monitor_file(
                Gio.FileMonitorFlags.NONE, None
            )
            monitor.connect("changed", self._state_changed)
            self.state_monitor = monitor
        except GLib.Error:
            GLib.timeout_add(500, self._watch_state)

    def call(self, *args: str) -> None:
        print(f"[frieren-tray] ipc {' '.join(args)}", flush=True)
        try:
            subprocess.Popen(
                [self.qs, "-c", CONFIG_NAME, "ipc", "call", CONFIG_NAME, *args],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:
            print(f"[frieren-tray] ipc failed: {exc}", file=sys.stderr, flush=True)

    def _register(self) -> bool:
        try:
            watcher = self.bus_connection.get_object(
                "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher"
            )
            dbus.Interface(watcher, "org.kde.StatusNotifierWatcher").RegisterStatusNotifierItem(
                self.service
            )
            print("[frieren-tray] registered with StatusNotifierWatcher", flush=True)
            return False
        except Exception as exc:
            print(f"[frieren-tray] waiting for StatusNotifierWatcher: {exc}",
                  file=sys.stderr, flush=True)
            return True

    def _reregister(self) -> bool:
        try:
            watcher = self.bus_connection.get_object(
                "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher"
            )
            properties = dbus.Interface(watcher, "org.freedesktop.DBus.Properties")
            items = properties.Get(
                "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"
            )
            # The watcher lists entries as "service/object-path".
            if not any(str(item).startswith(self.service) for item in items):
                self._register()
        except Exception:
            pass
        return True

def main() -> int:
    if len(sys.argv) < 6:
        print("usage: tray.py ICON.png ICON-128.argb ICON-64.argb ICON-32.argb STATE.json",
              file=sys.stderr)
        return 2

    icon_png = sys.argv[1]
    argb_paths = {128: sys.argv[2], 64: sys.argv[3], 32: sys.argv[4]}
    state_path = sys.argv[5]

    set_parent_death_signal()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    connection = dbus.SessionBus()
    try:
        bus_name = dbus.service.BusName(BUS_NAME, connection, replace_existing=False)
    except dbus.exceptions.NameExistsException:
        print("[frieren-tray] another tray helper is already running", file=sys.stderr)
        return 0

    loop = GLib.MainLoop()
    FrierenItem(connection, bus_name, icon_png, argb_paths, state_path, loop)
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    signal.signal(signal.SIGINT, lambda *_: loop.quit())
    loop.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

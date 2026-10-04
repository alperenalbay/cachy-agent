#!/usr/bin/env python3
"""Plasma action'lı bildirim: notify-send action desteklemez, bu yüzden Gio."""
import os
import sys, subprocess, shlex
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib


def main():
    title, body, action_cmd = sys.argv[1], sys.argv[2], sys.argv[3]
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    proxy = Gio.DBusProxy.new_sync(conn, Gio.DBusProxyFlags.NONE, None,
        "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications", None)
    res = proxy.call_sync("Notify", GLib.Variant("(susssasa{sv}i)", (
        "cachy-agent", 0, "utilities-terminal", title, body,
        ["incele", "Agent ile İncele", "sessize-al", "Sessize Al"],
        {}, 15000)), Gio.DBusCallFlags.NONE, -1, None)
    notif_id = res.unpack()[0]

    loop = GLib.MainLoop()

    def on_signal(conn2, sender, path, iface, sig, params, user_data=None):
        if sig == "ActionInvoked" and params.unpack()[0] == notif_id:
            action = params.unpack()[1]
            if action == "incele":
                subprocess.Popen(shlex.split(action_cmd))
            elif action == "sessize-al":
                open(os.path.expanduser("~/.config/cachy-agent/mute-all"), "a").close()
            loop.quit()

    conn.signal_subscribe(None, "org.freedesktop.Notifications", "ActionInvoked",
        "/org/freedesktop/Notifications", None, Gio.DBusSignalFlags.NONE, on_signal, None)
    GLib.timeout_add_seconds(300, loop.quit)
    loop.run()


if __name__ == "__main__":
    main()

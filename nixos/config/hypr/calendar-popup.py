#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk

CSS = b"""
window {
    background-color: #24273a;
    border: 1px solid #363a4f;
    border-radius: 12px;
    padding: 12px;
}
calendar {
    background-color: #24273a;
    color: #cad3f5;
    border: none;
    padding: 4px;
    font-family: "MesloLGS NF";
    font-size: 13px;
}
calendar:selected {
    background-color: #c6a0f6;
    color: #1e2030;
    border-radius: 50%;
}
calendar.header {
    color: #c6a0f6;
    font-weight: bold;
    padding-bottom: 8px;
}
calendar.button {
    color: #8aadf4;
    background: transparent;
    border: none;
}
calendar:indeterminate {
    color: #494d64;
}
"""

win = Gtk.Window()
win.set_decorated(False)
win.set_resizable(False)
win.set_skip_taskbar_hint(True)
win.set_keep_above(True)

provider = Gtk.CssProvider()
provider.load_from_data(CSS)
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(), provider,
    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
)

win.add(Gtk.Calendar())
win.connect("destroy", Gtk.main_quit)
win.connect("focus-out-event", lambda *_: Gtk.main_quit())
win.connect("key-press-event", lambda w, e: Gtk.main_quit() if e.keyval == Gdk.KEY_Escape else None)

win.show_all()

w, _ = win.get_size()
sw = Gdk.Screen.get_default().get_width()
win.move((sw - w) // 2, 62)
win.present()
win.grab_focus()

Gtk.main()

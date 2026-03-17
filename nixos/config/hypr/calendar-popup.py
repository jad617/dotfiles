#!/usr/bin/env python3
# =============================================================================
# calendar-popup.py — Catppuccin Macchiato calendar popup for Waybar
# Closes when clicking outside (focus-out). Positioned below the bar.
# =============================================================================
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

class CalendarPopup(Gtk.Window):
    def __init__(self):
        super().__init__()
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_type_hint(Gdk.WindowTypeHint.POPUP_MENU)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        self.add(Gtk.Calendar())
        self.connect("focus-out-event", lambda *_: Gtk.main_quit())
        self.connect("key-press-event", self._on_key)
        self.connect("destroy", Gtk.main_quit)

        self.show_all()

        # Position: centered horizontally, just below the bar (40px + 8 margin + 10 gap)
        w, _ = self.get_size()
        sw = Gdk.Screen.get_default().get_width()
        self.move((sw - w) // 2, 62)
        self.present()
        self.grab_focus()

    def _on_key(self, _, event):
        if event.keyval == Gdk.KEY_Escape:
            Gtk.main_quit()

CalendarPopup()
Gtk.main()

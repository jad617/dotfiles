#!/usr/bin/env python3
# Calendar popup — tkinter (stdlib, no extra deps)
# Catppuccin Macchiato colours. Closes on focus-out or Escape.
import tkinter as tk
import calendar
from datetime import date

BG      = "#24273a"
FG      = "#cad3f5"
MAUVE   = "#c6a0f6"
BLUE    = "#8aadf4"
SURFACE = "#363a4f"
DIM     = "#494d64"
TODAY   = "#ed8796"
FONT    = ("MesloLGS NF", 11)
FONT_B  = ("MesloLGS NF", 11, "bold")

class CalendarPopup(tk.Tk):
    def __init__(self):
        super().__init__()
        self.overrideredirect(True)       # no window decorations
        self.attributes("-topmost", True)
        self.configure(bg=BG)

        now = date.today()
        self.year  = now.year
        self.month = now.month
        self.today = now

        self._build()
        self._render()

        self.update_idletasks()
        sw = self.winfo_screenwidth()
        w  = self.winfo_reqwidth()
        self.geometry(f"+{(sw - w) // 2}+62")

        self.bind("<Escape>", lambda _: self.destroy())
        self.bind("<FocusOut>", lambda _: self.destroy())
        self.focus_force()

    def _build(self):
        # Header: prev / Month Year / next
        hdr = tk.Frame(self, bg=BG)
        hdr.pack(fill="x", padx=12, pady=(12, 4))
        tk.Button(hdr, text="◀", bg=BG, fg=BLUE, bd=0, cursor="hand2",
                  font=FONT, command=self._prev).pack(side="left")
        self.title_lbl = tk.Label(hdr, bg=BG, fg=MAUVE, font=FONT_B)
        self.title_lbl.pack(side="left", expand=True)
        tk.Button(hdr, text="▶", bg=BG, fg=BLUE, bd=0, cursor="hand2",
                  font=FONT, command=self._next).pack(side="right")

        # Day-of-week headers
        days_frame = tk.Frame(self, bg=BG)
        days_frame.pack(padx=12)
        for d in ["Mo","Tu","We","Th","Fr","Sa","Su"]:
            tk.Label(days_frame, text=d, bg=BG, fg=DIM,
                     font=FONT_B, width=3).pack(side="left")

        # Grid of day buttons
        self.grid_frame = tk.Frame(self, bg=BG)
        self.grid_frame.pack(padx=12, pady=(2, 12))

    def _render(self):
        for w in self.grid_frame.winfo_children():
            w.destroy()
        self.title_lbl.config(text=date(self.year, self.month, 1).strftime("%B %Y"))
        weeks = calendar.monthcalendar(self.year, self.month)
        for week in weeks:
            row = tk.Frame(self.grid_frame, bg=BG)
            row.pack()
            for day in week:
                is_today = (day == self.today.day and
                            self.month == self.today.month and
                            self.year  == self.today.year)
                txt = str(day) if day else ""
                fg  = TODAY if is_today else FG if day else DIM
                bg  = SURFACE if is_today else BG
                tk.Label(row, text=txt, bg=bg, fg=fg, font=FONT,
                         width=3, pady=2).pack(side="left")

    def _prev(self):
        self.month -= 1
        if self.month == 0:
            self.month, self.year = 12, self.year - 1
        self._render()

    def _next(self):
        self.month += 1
        if self.month == 13:
            self.month, self.year = 1, self.year + 1
        self._render()

CalendarPopup().mainloop()

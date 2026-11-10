-- =============================================================================
-- Hyprland configuration — Catppuccin Macchiato
-- Lua config (Hyprland 0.57+ no longer reads hyprland.conf)
-- API reference: share/hypr/stubs/hl.meta.lua in the Hyprland package
-- =============================================================================

-- Settings saved from HyprMod (the Hyprland settings app) live in
-- hyprland-gui.lua, loaded at the end so they override the values below

-- ---------------------------------------------------------------------------
-- Wayland environment
-- ---------------------------------------------------------------------------
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("NIXOS_OZONE_WL", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Adwaita")

-- ---------------------------------------------------------------------------
-- Monitors: fallback for any monitor, then the lines nwg-displays writes to
-- monitors.conf ("monitor=NAME,MODE,POSITION,SCALE"). kanshi also manages
-- layouts when monitors are plugged in.
-- ---------------------------------------------------------------------------
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

local monitors = io.open(os.getenv("HOME") .. "/.config/hypr/monitors.conf", "r")
if monitors then
    for line in monitors:lines() do
        local output, mode, position, scale =
            line:match("^%s*monitor%s*=%s*([^,]*),([^,]*),([^,]*),([^,%s]*)")
        if output then
            hl.monitor({ output = output, mode = mode, position = position, scale = tonumber(scale) or scale })
        end
    end
    monitors:close()
end

-- ---------------------------------------------------------------------------
-- Autostart
-- ---------------------------------------------------------------------------
hl.on("hyprland.start", function()
    -- Caelestia shell: bar, launcher, notifications, lock screen, idle, wallpaper
    hl.exec_cmd("caelestia shell -d")
    hl.exec_cmd("kanshi")
    -- First login only: default wallpaper and the light theme generated from it
    -- (Caelestia keeps whatever is picked later: launcher >wallpaper, >scheme)
    hl.exec_cmd("[ -f ~/.local/state/caelestia/wallpaper/path.txt ] || { caelestia wallpaper -f ~/Pictures/Wallpapers/quasar.webp; caelestia scheme set -n dynamic -m light; }")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("/run/current-system/sw/bin/wezterm")
end)

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll       = false,
            disable_while_typing = true,
        },
    },

    general = {
        gaps_in     = 8,
        gaps_out    = 16,
        border_size = 2,

        -- Catppuccin Macchiato — mauve → blue gradient on active, surface0 on inactive
        col = {
            active_border   = { colors = { "rgba(c6a0f6ff)", "rgba(8aadf4ff)" }, angle = 45 },
            inactive_border = "rgba(363a4f99)",
        },

        layout           = "dwindle",
        allow_tearing    = false,
        resize_on_border = true,
    },

    decoration = {
        rounding = 12,

        -- Off: Caelestia's panels are made opaque instead (config/caelestia/shell.json)
        blur   = { enabled = false },
        shadow = { enabled = false },

        active_opacity     = 1.0,
        inactive_opacity   = 1.0,
        fullscreen_opacity = 1.0,
    },

    animations = {
        enabled = false,
    },

    dwindle = {
        preserve_split = true,
        smart_resizing = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        animate_manual_resizes   = true,
        focus_on_activate        = true,
    },
})

-- ---------------------------------------------------------------------------
-- Window rules
-- ---------------------------------------------------------------------------
hl.window_rule({ name = "pavucontrol", match = { class = "pavucontrol" }, float = true, size = "900 600", center = true })
hl.window_rule({ name = "blueman", match = { class = "blueman-manager" }, float = true, size = "900 600", center = true })
hl.window_rule({ name = "nm-editor", match = { class = "nm-connection-editor" }, float = true })
hl.window_rule({ name = "nautilus", match = { class = "org.gnome.Nautilus" }, float = true })
hl.window_rule({ name = "calendar", match = { class = "org.gnome.Calendar" }, float = true, size = "900 700", center = true })

-- Firefox / Chromium picture-in-picture
hl.window_rule({ name = "pip", match = { title = "Picture-in-Picture" }, float = true, pin = true })

-- ---------------------------------------------------------------------------
-- Keybinds — modifier: SUPER (Win key; ⌘ in UTM)
-- ---------------------------------------------------------------------------
local exec = hl.dsp.exec_cmd
local dirs = { left = "left", right = "right", up = "up", down = "down", H = "left", J = "down", K = "up", L = "right" }

-- ── Launchers ───────────────────────────────────────────────────────────────
hl.bind("SUPER + Return", exec("wezterm"))
-- Over IPC: the caelestia:launcher shortcut only toggles on key release
hl.bind("SUPER + D", exec("caelestia shell drawers toggle launcher"))
hl.bind("SUPER + E", exec("nautilus"))
hl.bind("SUPER + B", exec('sh -c \'exec "$BROWSER"\''))
hl.bind("CTRL + ALT + H", exec("pkill fuzzel || caelestia clipboard"))

-- ── Caelestia ───────────────────────────────────────────────────────────────
hl.bind("SUPER + N", hl.dsp.global("caelestia:sidebar"))
hl.bind("CTRL + ALT + Delete", hl.dsp.global("caelestia:session"))
hl.bind("SUPER + L", hl.dsp.global("caelestia:lock"))
hl.bind("CTRL + SUPER + SHIFT + R", exec("caelestia shell -k; caelestia shell -d"))

-- ── Screenshots ─────────────────────────────────────────────────────────────
hl.bind("Print", exec("grimblast copy area"))
hl.bind("SHIFT + Print", exec("grimblast copy output"))
hl.bind("SUPER + Print", exec("grimblast copysave output ~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png"))

-- ── Window management ───────────────────────────────────────────────────────
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + P", hl.dsp.window.pseudo())
hl.bind("SUPER + G", hl.dsp.group.toggle())

-- ── Focus / move / resize: arrows and H J K L ───────────────────────────────
-- SUPER + L is the lock screen, so focus-right is only on the arrow key
local resize = { left = { -50, 0 }, right = { 50, 0 }, up = { 0, -50 }, down = { 0, 50 } }
for key, dir in pairs(dirs) do
    if key ~= "L" then
        hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = dir }))
    end
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
    local d = resize[dir]
    hl.bind("SUPER + ALT + " .. key, hl.dsp.window.resize({ x = d[1], y = d[2], relative = true }), { repeating = true })
end

-- ── Workspaces ──────────────────────────────────────────────────────────────
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("CTRL + ALT + up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("CTRL + ALT + down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("CTRL + ALT + SHIFT + up", hl.dsp.window.move({ workspace = "e-1" }))
hl.bind("CTRL + ALT + SHIFT + down", hl.dsp.window.move({ workspace = "e+1" }))

-- Special workspace (scratchpad)
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind("SUPER + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- ── Media / volume / brightness ─────────────────────────────────────────────
hl.bind("XF86AudioRaiseVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioPlay", exec("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", exec("playerctl previous"), { locked = true })
hl.bind("XF86AudioNext", exec("playerctl next"), { locked = true })
hl.bind("XF86MonBrightnessUp", exec("brightnessctl s 10%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", exec("brightnessctl s 10%-"), { locked = true, repeating = true })

-- ── Mouse: drag to move, right-drag to resize ───────────────────────────────
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ---------------------------------------------------------------------------
-- HyprMod managed settings (last, so changes made in the app win)
-- ---------------------------------------------------------------------------
require("hyprland-gui")

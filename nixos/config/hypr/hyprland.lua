-- =============================================================================
-- Hyprland configuration — Catppuccin Macchiato
-- Lua config (Hyprland 0.57+ no longer reads hyprland.conf)
-- API reference: share/hypr/stubs/hl.meta.lua in the Hyprland package
-- =============================================================================

-- Settings saved from HyprMod (the Hyprland settings app) live in
-- hyprland-gui.lua, loaded at the end so they override the values below

-- ---------------------------------------------------------------------------
-- Environment: the Wayland variables (Qt, Electron, Java…) come from the login
-- (environment.sessionVariables in configuration.nix); only the cursor here
-- ---------------------------------------------------------------------------
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Adwaita")

-- ---------------------------------------------------------------------------
-- Monitors: fallback for any monitor, then the desk layouts below, then the
-- lines nwg-displays writes to monitors.conf ("monitor=NAME,MODE,POSITION,SCALE").
-- ---------------------------------------------------------------------------
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Desk layouts: screens pinned by model (desc:), so the order survives KVM
-- switches (with "auto", whichever screen reconnects first ends up on the
-- left). A desk's positions apply only while ALL its screens are connected;
-- any other mix (a laptop with one of them, a different desk) stays "auto".
-- The same config runs on every machine: add a desk = add an entry.
local desks = {
    { -- home desk: LG on the left, ViewSonic on the right
        { desc = "LG Electronics LG HDR WFHD 0x0005B707", position = "0x0" },
        { desc = "ViewSonic Corporation VA2246 SERIES TSP154382384", position = "2560x0" },
    },
}
local function apply_desks()
    local connected = {}
    for _, m in ipairs(hl.get_monitors()) do
        connected[m.description] = true
    end
    for _, desk in ipairs(desks) do
        local complete = true
        for _, screen in ipairs(desk) do
            complete = complete and connected[screen.desc] == true
        end
        for _, screen in ipairs(desk) do
            hl.monitor({ output = "desc:" .. screen.desc, mode = "preferred",
                position = complete and screen.position or "auto", scale = 1 })
        end
    end
end
apply_desks() -- screens connected now (a reload); at login they arrive later: monitor.added

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
-- Auto-login from greetd (CAELESTIA_AUTOLOCK=1): Caelestia's lock screen is
-- the login screen. Keybinds are off in this empty submap until autolock.sh
-- confirms the lock (it logs out if it can't), and windows start only after.
-- (Hyprland ignores a submap with no binds, hence the do-nothing one)
hl.define_submap("autolock", function()
    hl.bind("SUPER + F12", hl.dsp.no_op())
end)
local autolock = os.getenv("CAELESTIA_AUTOLOCK") == "1"

hl.on("hyprland.start", function()
    if autolock then
        hl.dispatch(hl.dsp.submap("autolock"))
    end
    -- Caelestia shell: bar, launcher, notifications, lock screen, idle, wallpaper
    hl.exec_cmd("caelestia shell -d")
    -- First login only: default wallpaper and the light theme generated from it
    -- (Caelestia keeps whatever is picked later: launcher >wallpaper, >scheme)
    hl.exec_cmd("[ -f ~/.local/state/caelestia/wallpaper/path.txt ] || { caelestia wallpaper -f ~/Pictures/Wallpapers/quasar.webp; caelestia scheme set -n dynamic -m light; }")
    hl.exec_cmd("wl-paste --watch cliphist store")
    if autolock then
        hl.exec_cmd("bash ~/.config/hypr/autolock.sh /run/current-system/sw/bin/wezterm")
    else
        hl.exec_cmd("/run/current-system/sw/bin/wezterm")
    end
end)

-- KVM switching unplugs every screen at once; Wayland clients lose their
-- outputs and Caelestia (and the GTK portal / polkit agent) exit. When a
-- screen comes back, restart whatever died.
hl.on("monitor.added", function()
    apply_desks()
    hl.exec_cmd("pgrep -u \"$USER\" -f 'share/caelestia-shell' >/dev/null || caelestia shell -d")
    hl.exec_cmd("systemctl --user restart --no-block xdg-desktop-portal-gtk.service polkit-agent.service")
end)
-- A desk screen unplugged: the others of that desk go back to "auto"
hl.on("monitor.removed", function() apply_desks() end)

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

    -- Tab groups (SUPER + G): orange like WezTerm's borders, not the default
    -- see-through yellow; the dimmer one is a group without focus
    group = {
        col = {
            border_active   = "rgba(ff5f1fff)",
            border_inactive = "rgba(ff5f1f66)",
        },
        groupbar = {
            col = {
                active   = "rgba(ff5f1fff)",
                inactive = "rgba(ff5f1f55)",
            },
        },
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
        force_split    = 2,     -- new windows open right / below, wherever the mouse is
        smart_resizing = true,
    },

    master = {
        new_status = "master",
    },

    -- No switch to HDR for fullscreen apps. The LG is HDR-capable, and fullscreen
    -- Chrome made it go HDR and show its (SDR) pages very dark; desktop stays sRGB
    render = {
        cm_auto_hdr = 0,
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

-- Every bind has a description, "Group: what it does": nixos-shortcuts
-- (nixos/bin) lists them from the running Hyprland, grouped, so keep one on
-- each new bind (one without shows up under "Other")

-- ── Launchers ───────────────────────────────────────────────────────────────
hl.bind("SUPER + Return", exec("wezterm"), { description = "Apps: Terminal (WezTerm)" })
-- Over IPC: the caelestia:launcher shortcut only toggles on key release
hl.bind("SUPER + D", exec("caelestia shell drawers toggle launcher"), { description = "Apps: Launcher" })
hl.bind("SUPER + E", exec("nautilus"), { description = "Apps: Files (Nautilus)" })
hl.bind("SUPER + B", exec("bash ~/.config/hypr/browser.sh"), { description = "Apps: Browser (cursor in the address bar)" })
hl.bind("CTRL + ALT + H", exec("pkill fuzzel || caelestia clipboard"), { description = "Clipboard: History" })

-- ── Copy / paste on ALT (the ⌘ position), like macOS and the Pop!_OS keyd setup
-- Other apps get CTRL + C / V. WezTerm gets ALT + C / V passed through, since
-- CTRL + C there would interrupt the running command (wezterm.lua copies/pastes).
local function clipboard_key(key)
    return function()
        local w = hl.get_active_window()
        local mods = (w and w.class == "org.wezfurlong.wezterm") and "ALT" or "CTRL"
        hl.dispatch(hl.dsp.send_shortcut({ mods = mods, key = key }))
    end
end
hl.bind("ALT + C", clipboard_key("c"), { description = "Clipboard: Copy" })
hl.bind("ALT + V", clipboard_key("v"), { description = "Clipboard: Paste" })

-- ── CTRL + D: WezTerm gets it unchanged (EOF, closes the shell); Chrome closes
-- the tab (CTRL + W) instead of bookmarking; everything else closes the window
-- (like SUPER + Q)
local browsers = { ["google-chrome"] = true, ["chromium-browser"] = true, ["chromium"] = true }
hl.bind("CTRL + D", function()
    local w = hl.get_active_window()
    if not w then return end
    if w.class == "org.wezfurlong.wezterm" then
        hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL", key = "d" }))
    elseif browsers[w.class] then
        hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL", key = "w" }))
    else
        hl.dispatch(hl.dsp.window.close())
    end
end, { description = "Windows: Close (CTRL + D; tab in Chrome, EOF in WezTerm)" })

-- ── Caelestia ───────────────────────────────────────────────────────────────
hl.bind("SUPER + N", hl.dsp.global("caelestia:sidebar"), { description = "Shell: Sidebar (notifications)" })
-- Hover-to-open is off (config/caelestia/shell.json), so the dashboard is on a key
hl.bind("SUPER + A", hl.dsp.global("caelestia:dashboard"), { description = "Shell: Dashboard" })
hl.bind("CTRL + ALT + Delete", hl.dsp.global("caelestia:session"), { description = "Shell: Session menu (log out, reboot, power off)" })
hl.bind("SUPER + L", hl.dsp.global("caelestia:lock"), { description = "Shell: Lock screen" })
hl.bind("CTRL + SUPER + SHIFT + R", exec("~/.local/bin/caelestia-restart"), { description = "Shell: Restart Caelestia (any build; not while locked)" })

-- ── Screenshots ─────────────────────────────────────────────────────────────
-- Saved as ~/Pictures/screenshots/YYYYMMDD_HHMMSS.png (folder made if missing,
-- e.g. ~/Pictures is the shared drive), and on the clipboard. The capital
-- ~/Pictures/Screenshots is Pop!_OS's
local shot = "mkdir -p ~/Pictures/screenshots && grimblast copysave %s ~/Pictures/screenshots/$(date +%%Y%%m%%d_%%H%%M%%S).png"
hl.bind("Print", exec(shot:format("area")), { description = "Screenshots: Area, saved + clipboard" })
-- The Logitech keyboard's screenshot key sends SUPER + SHIFT + S (the Windows snip shortcut)
hl.bind("SUPER + SHIFT + S", exec(shot:format("area")), { description = "Screenshots: Area, saved + clipboard" })
hl.bind("SHIFT + Print", exec("grimblast copy output"), { description = "Screenshots: Screen, to the clipboard" })
hl.bind("SUPER + Print", exec(shot:format("output")), { description = "Screenshots: Screen, saved + clipboard" })

-- ── Window management ───────────────────────────────────────────────────────
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Windows: Close" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "Windows: Fullscreen" })
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }), { description = "Windows: Maximize (bar stays)" })
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }), { description = "Windows: Float / tile" })
hl.bind("SUPER + P", hl.dsp.window.pseudo(), { description = "Windows: Pseudo-tile" })
hl.bind("SUPER + G", hl.dsp.group.toggle(), { description = "Groups: Make / break up a tab group" })
hl.bind("SUPER + Tab", hl.dsp.group.next(), { description = "Groups: Next tab" })
hl.bind("SUPER + SHIFT + Tab", hl.dsp.group.prev(), { description = "Groups: Previous tab" })
hl.bind("SUPER + U", hl.dsp.window.move({ out_of_group = true }), { description = "Groups: Pop the tab out of its group" })
hl.bind("SUPER + T", hl.dsp.layout("togglesplit"), { description = "Windows: Flip the split (side by side <-> stacked)" })

-- Where the next window opens: by default it splits the focused window along
-- its longer side, to the right or below (dwindle.force_split). SUPER + CTRL +
-- direction picks the side for the next window only.
local pre = { left = "l", right = "r", up = "u", down = "d" }
for _, key in ipairs({ "left", "H", "down", "J", "up", "K", "right", "L" }) do
    hl.bind("SUPER + CTRL + " .. key, hl.dsp.layout("preselect " .. pre[dirs[key]]),
        { description = "Windows: Next window opens " .. ({ left = "left", right = "right", up = "above", down = "below" })[dirs[key]] })
end

-- ── Focus / move / resize: arrows and H J K L ───────────────────────────────
-- SUPER + L is the lock screen, so focus-right is only on the arrow key
-- (in a fixed order, arrow then letter, so nixos-shortcuts lists them that way)
local resize = { left = { -50, 0 }, right = { 50, 0 }, up = { 0, -50 }, down = { 0, 50 } }
local order = { "left", "H", "down", "J", "up", "K", "right", "L" }
for _, key in ipairs(order) do
    if key ~= "L" then
        hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = dirs[key] }), { description = "Focus: Focus " .. dirs[key] })
    end
end
-- SUPER + SHIFT + direction moves the window. A window that is itself in a tab
-- group (SUPER + G) joins the group on that side instead, as a new tab; a
-- window without a group always just moves
local function neighbour(w, dir)
    local ax, ay, aw, ah = w.at.x, w.at.y, w.size.x, w.size.y
    local best, bestGap
    for _, o in ipairs(hl.get_windows()) do
        if o.address ~= w.address and o.mapped and not o.hidden and not o.floating
            and o.workspace and w.workspace and o.workspace.id == w.workspace.id then
            local bx, by, bw, bh = o.at.x, o.at.y, o.size.x, o.size.y
            local gap, overlap
            if dir == "left" or dir == "right" then
                gap = dir == "left" and ax - (bx + bw) or bx - (ax + aw)
                overlap = math.min(ay + ah, by + bh) - math.max(ay, by)
            else
                gap = dir == "up" and ay - (by + bh) or by - (ay + ah)
                overlap = math.min(ax + aw, bx + bw) - math.max(ax, bx)
            end
            if gap > -10 and overlap > 0 and (not bestGap or gap < bestGap) then
                best, bestGap = o, gap
            end
        end
    end
    return best
end
local function move_or_join(dir)
    return function()
        local w = hl.get_active_window()
        if not w then return end
        local o = neighbour(w, dir)
        if w.group and o and o.group and tostring(w.group) ~= tostring(o.group) then
            hl.dispatch(hl.dsp.window.move({ into_group = dir }))
        else
            hl.dispatch(hl.dsp.window.move({ direction = dir }))
        end
    end
end
for _, key in ipairs(order) do
    hl.bind("SUPER + SHIFT + " .. key, move_or_join(dirs[key]), { description = "Focus: Move window " .. dirs[key] .. " (a grouped one joins the group there)" })
end
for _, key in ipairs(order) do
    local d = resize[dirs[key]]
    hl.bind("SUPER + ALT + " .. key, hl.dsp.window.resize({ x = d[1], y = d[2], relative = true }),
        { repeating = true, description = "Focus: Resize window " .. dirs[key] })
end

-- ── Workspaces ──────────────────────────────────────────────────────────────
-- Each screen has its own slots 1–SLOTS (5). Screens are numbered left to
-- right, and each gets a block of 10 workspace ids: slot N is workspace N on
-- the 1st screen, 10+N on the 2nd, 20+N on the 3rd… (port names don't matter,
-- so this survives screens being re-plugged).
--
-- SUPER + W toggles how the slot keys behave:
--   paired – all screens switch together (left N, right 10+N)
--   locked – one screen stays put, the others switch (together, if several),
--            even with focus on the locked one. The locked screen is the one
--            that had focus when SUPER + W locked it (named in the
--            notification). To lock another one: focus it, SUPER + W twice
local SLOTS = 5 -- slots per screen: SUPER + 1–5, CTRL + ALT + arrows cycle 1 → 5
local mode = "paired"
local locked_name -- name of the locked screen

local function screens()
    local list = hl.get_monitors()
    table.sort(list, function(a, b) return a.position.x < b.position.x end)
    return list
end

local function screen_index(list, mon)
    for i, m in ipairs(list) do
        if m.name == mon.name then return i end
    end
    return 1
end

local function slot_of(id)
    return ((id - 1) % 10) + 1
end

-- Whether the slot keys leave this screen alone (locked, and more than one
-- screen: with only the locked one left, it switches as usual)
local function frozen(list, s)
    return mode == "locked" and #list > 1 and s.name == locked_name
end

-- The screen the slot keys act on: the focused one, or when that one is
-- locked, the first screen that isn't
local function base_screen(list, active)
    if frozen(list, active) then
        for _, s in ipairs(list) do
            if not frozen(list, s) then return s end
        end
    end
    return active
end

-- Hyprland sends no "workspace" event when a screen without focus switches,
-- so Caelestia's bar on it wouldn't update (or animate). Focus going over to
-- that screen and back sends "focusedmon", which makes it re-read the screens;
-- warps are off meanwhile, so the cursor doesn't move
local function announce(name, back)
    local warps = hl.get_config("cursor.no_warps")
    hl.config({ cursor = { no_warps = true } })
    hl.dispatch(hl.dsp.focus({ monitor = name }))
    hl.dispatch(hl.dsp.focus({ monitor = back }))
    hl.config({ cursor = { no_warps = warps } })
end

-- Every screen that isn't locked goes to slot N; focus stays where it is,
-- moving with the switch only when the focused screen is one of them
local function show(n)
    local list, active = screens(), hl.get_active_monitor()
    if not active then return end
    local switched
    for i, s in ipairs(list) do
        if s.name ~= active.name and not frozen(list, s) then
            s:set_workspace((i - 1) * 10 + n)
            switched = switched or s.name
        end
    end
    if not frozen(list, active) then
        -- this focus change sends "workspace": every bar re-reads its screen
        hl.dispatch(hl.dsp.focus({ workspace = (screen_index(list, active) - 1) * 10 + n }))
    elseif switched then
        announce(switched, active.name)
    end
end

-- From the locked screen this sends the window to a screen that isn't locked
local function send(n)
    local list, active = screens(), hl.get_active_monitor()
    if not active then return end
    local ws = (screen_index(list, base_screen(list, active)) - 1) * 10 + n
    hl.dispatch(hl.dsp.window.move({ workspace = ws }))
    -- If focus followed the window, bring the other screens along
    local now = hl.get_active_monitor()
    if now and now.active_workspace and now.active_workspace.id == ws then
        show(n)
    end
end

-- Next/previous slot (wraps SLOTS → 1), measured on the screen the keys act on
local function step(d, fn)
    local list, active = screens(), hl.get_active_monitor()
    if not active then return end
    local ws = base_screen(list, active).active_workspace
    local cur = ws and ws.id and ws.id > 0 and math.min(slot_of(ws.id), SLOTS) or 1
    fn((cur - 1 + d) % SLOTS + 1)
end

for i = 1, SLOTS do
    local key = i % 10 -- 10 maps to key 0
    hl.bind("SUPER + " .. key, function() show(i) end, { description = "Workspaces: Go to slot 1–" .. SLOTS })
    hl.bind("SUPER + SHIFT + " .. key, function() send(i) end, { description = "Workspaces: Send window to slot 1–" .. SLOTS })
end

hl.bind("SUPER + W", function()
    local active = hl.get_active_monitor()
    if not active then return end
    if mode == "paired" then
        mode, locked_name = "locked", active.name
        -- "LG Electronics LG HDR WFHD 0x0005B707" -> "LG Electronics LG HDR WFHD"
        local label = (active.description or "") ~= "" and active.description or active.name
        local serial = active.serial or ""
        if serial ~= "" and label:sub(-#serial) == serial then label = label:sub(1, -#serial - 2) end
        hl.notification.create({ text = "Workspaces: " .. label .. " locked, stays put", timeout = 2000 })
    else
        mode, locked_name = "paired", nil
        hl.notification.create({ text = "Workspaces: paired", timeout = 2000 })
        -- Line the other screens up with the focused one
        local ws = active.active_workspace
        if ws and ws.id and ws.id > 0 then show(slot_of(ws.id)) end
    end
end, { description = "Workspaces: Toggle paired / locked (the focused screen stays put)" })

hl.bind("SUPER + mouse_down", function() step(1, show) end, { description = "Workspaces: Next slot" })
hl.bind("SUPER + mouse_up", function() step(-1, show) end, { description = "Workspaces: Previous slot" })
hl.bind("CTRL + ALT + up", function() step(-1, show) end, { description = "Workspaces: Previous slot" })
hl.bind("CTRL + ALT + down", function() step(1, show) end, { description = "Workspaces: Next slot" })
hl.bind("CTRL + ALT + SHIFT + up", function() step(-1, send) end, { description = "Workspaces: Send window to the previous slot" })
hl.bind("CTRL + ALT + SHIFT + down", function() step(1, send) end, { description = "Workspaces: Send window to the next slot" })

-- Special workspace (scratchpad)
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("magic"), { description = "Workspaces: Scratchpad, show / hide" })
hl.bind("SUPER + CTRL + S", hl.dsp.window.move({ workspace = "special:magic" }), { description = "Workspaces: Scratchpad, send window there" })

-- ── Media / volume / brightness ─────────────────────────────────────────────
hl.bind("XF86AudioRaiseVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { description = "Media: Volume up", locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { description = "Media: Volume down", locked = true, repeating = true })
hl.bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { description = "Media: Mute", locked = true })
hl.bind("XF86AudioMicMute", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { description = "Media: Mute the microphone", locked = true })
hl.bind("XF86AudioPlay", exec("playerctl play-pause"), { description = "Media: Play / pause", locked = true })
hl.bind("XF86AudioPrev", exec("playerctl previous"), { description = "Media: Previous track", locked = true })
hl.bind("XF86AudioNext", exec("playerctl next"), { description = "Media: Next track", locked = true })
-- Caelestia sets the focused screen's brightness (backlight, or DDC/CI on
-- desktop monitors) and shows its OSD; F1 / F2 send these keys (keyd)
hl.bind("XF86MonBrightnessUp", hl.dsp.global("caelestia:brightnessUp"), { description = "Media: Brightness up (F2)", locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("caelestia:brightnessDown"), { description = "Media: Brightness down (F1)", locked = true, repeating = true })
-- SHIFT + F1 / F2: every screen at once (Caelestia's brightness IPC, per screen)
local function all_screens_brightness(direction)
    return function()
        for _, m in ipairs(hl.get_monitors()) do
            hl.dispatch(hl.dsp.exec_cmd("caelestia shell brightness stepFor " .. m.name .. " " .. direction))
        end
    end
end
hl.bind("SHIFT + XF86MonBrightnessUp", all_screens_brightness("up"), { description = "Media: Brightness up, all screens (SHIFT + F2)", locked = true, repeating = true })
hl.bind("SHIFT + XF86MonBrightnessDown", all_screens_brightness("down"), { description = "Media: Brightness down, all screens (SHIFT + F1)", locked = true, repeating = true })

-- ── Mouse: drag to move, right-drag to resize ───────────────────────────────
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { description = "Mouse: Move a window", mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { description = "Mouse: Resize a window", mouse = true })

-- ---------------------------------------------------------------------------
-- HyprMod managed settings (last, so changes made in the app win)
-- ---------------------------------------------------------------------------
require("hyprland-gui")

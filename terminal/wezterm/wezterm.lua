--------------------------------------------------------------------------------
-- Locals
--------------------------------------------------------------------------------
local wezterm = require("wezterm")
local action = wezterm.action
local mux = wezterm.mux
local config = {}

--------------------------------------------------------------------------------
-- Global Config
--------------------------------------------------------------------------------
config.enable_kitty_graphics = true

wezterm.on("gui-startup", function(cmd)
	local tab, pane, window = mux.spawn_window(cmd or {})
	window:gui_window():maximize()
end)

config.window_padding = {
	left = 5,
	right = 0,
	top = 10,
	bottom = 0,
}

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------
if wezterm.target_triple:find("darwin") then
	-- macOS
	config.font_size = 13
elseif wezterm.target_triple:find("linux") then
	-- Linux
	config.font_size = 11
	config.enable_wayland = true
else
	-- Default fallback
	config.font_size = 12
end

config.font = wezterm.font("MesloLGS NF", { weight = "Bold" })
config.color_scheme = "Catppuccin Macchiato"
config.audible_bell = "Disabled"

-- Tab bar
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.tab_and_split_indices_are_zero_based = true

--------------------------------------------------------------------------------
-- Status bar — workspace name + time (right) + leader indicator (left)
-- Single handler: WezTerm only fires the last registered update-right-status
--------------------------------------------------------------------------------
local LEADER_ICON = utf8.char(0x1f7e2) -- green circle

wezterm.on("update-right-status", function(window, _)
	-- Right: broadcast indicator + workspace name + clock
	local name = wezterm.mux.get_active_workspace()
	local time = wezterm.strftime("%H:%M:%S")
	local bcast = wezterm.GLOBAL.broadcast and "📡 " or ""
	window:set_right_status(wezterm.format({
		{ Text = bcast .. " 󱂬  " .. name .. " | " .. time .. " " },
	}))

	-- Left: leader active indicator
	local SOLID_LEFT_ARROW = ""
	local ARROW_FOREGROUND = { Foreground = { Color = "#c6a0f6" } } -- mauve
	local prefix = ""

	if window:leader_is_active() then
		prefix = " " .. LEADER_ICON .. " "
		SOLID_LEFT_ARROW = utf8.char(0xe0b2)
	end

	if window:active_tab():tab_index() ~= 0 then
		ARROW_FOREGROUND = { Foreground = { Color = "#1e2030" } } -- mantle
	end

	window:set_left_status(wezterm.format({
		{ Text = prefix },
		ARROW_FOREGROUND,
		{ Text = SOLID_LEFT_ARROW },
	}))
end)

-- Toast when workspace changes
wezterm.on("workspace-changed", function(window, _)
	local ws = mux.get_active_workspace()
	window:toast_notification("Workspace", "Switched to: " .. (ws or "default"), nil, 3000)
end)

--------------------------------------------------------------------------------
-- Borders and inactive pane dimming
--------------------------------------------------------------------------------
config.colors = {
	split = "#ff5f1f", -- Neon orange split lines
}

config.inactive_pane_hsb = {
	saturation = 0.8,
	brightness = 0.7,
}

--------------------------------------------------------------------------------
-- Leader key (Ctrl+a, tmux-style)
--------------------------------------------------------------------------------
config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }

--------------------------------------------------------------------------------
-- Tab naming: show only current app, but allow renaming
--------------------------------------------------------------------------------
config.tab_max_width = 999
wezterm.on("format-tab-title", function(tab)
	local index = tostring(tab.tab_index)

	-- if you've renamed the tab, keep that name
	if tab.tab_title and tab.tab_title ~= "" then
		return " " .. index .. ": " .. tab.tab_title .. " "
	end

	-- otherwise show the current app (basename of the foreground process)
	local name = tab.active_pane.foreground_process_name or tab.active_pane.title or "?"
	local app = name:gsub("^.*/", "") -- strip path, keep just the program name

	return " " .. index .. ": " .. app .. " "
end)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
-- Detect (n)vim in the foreground
local function is_vim(pane)
	local p = pane:get_foreground_process_name()
	if not p then
		return false
	end
	p = p:lower()
	return p:find("n?vim") ~= nil
end

-- ALT resize that passes through to vim if running
local function alt_or_resize(key, resize_action)
	return wezterm.action_callback(function(window, pane)
		if is_vim(pane) then
			window:perform_action(action.SendKey({ key = key, mods = "ALT" }), pane)
		else
			window:perform_action(resize_action, pane)
		end
	end)
end

-- SHIFT+Arrow: pass to vim, else focus wezterm pane
local function shift_arrow_or_focus(dir, keyname)
	return wezterm.action_callback(function(window, pane)
		if is_vim(pane) then
			window:perform_action(action.SendKey({ key = keyname, mods = "SHIFT" }), pane)
		else
			window:perform_action(action.ActivatePaneDirection(dir), pane)
		end
	end)
end

--------------------------------------------------------------------------------
-- Broadcast mode: send all keystrokes to every pane in the current tab
--------------------------------------------------------------------------------
local function broadcast_send(text)
	return wezterm.action_callback(function(window, _)
		for _, p in ipairs(window:active_tab():panes()) do
			window:perform_action(action.SendString(text), p)
		end
	end)
end

local function broadcast_ctrl(c)
	return wezterm.action_callback(function(window, _)
		for _, p in ipairs(window:active_tab():panes()) do
			window:perform_action(action.SendKey({ key = c, mods = "CTRL" }), p)
		end
	end)
end

local broadcast_keys = {
	{ key = "a", mods = "LEADER", action = wezterm.action_callback(function(window, pane)
		wezterm.GLOBAL.broadcast = false
		window:perform_action(action.PopKeyTable, pane)
		window:toast_notification("Broadcast", "OFF", nil, 2000)
	end) },
	-- Special keys
	{ key = "Enter",      mods = "NONE", action = broadcast_send("\r") },
	{ key = "Backspace",  mods = "NONE", action = broadcast_send("\x7f") },
	{ key = "Tab",        mods = "NONE", action = broadcast_send("\t") },
	{ key = "Space",      mods = "NONE", action = broadcast_send(" ") },
	{ key = "Escape",     mods = "NONE", action = broadcast_send("\x1b") },
	{ key = "UpArrow",    mods = "NONE", action = broadcast_send("\x1b[A") },
	{ key = "DownArrow",  mods = "NONE", action = broadcast_send("\x1b[B") },
	{ key = "RightArrow", mods = "NONE", action = broadcast_send("\x1b[C") },
	{ key = "LeftArrow",  mods = "NONE", action = broadcast_send("\x1b[D") },
	-- Plain special chars
	{ key = "-",  mods = "NONE", action = broadcast_send("-") },
	{ key = "=",  mods = "NONE", action = broadcast_send("=") },
	{ key = "[",  mods = "NONE", action = broadcast_send("[") },
	{ key = "]",  mods = "NONE", action = broadcast_send("]") },
	{ key = "\\", mods = "NONE", action = broadcast_send("\\") },
	{ key = ";",  mods = "NONE", action = broadcast_send(";") },
	{ key = "'",  mods = "NONE", action = broadcast_send("'") },
	{ key = ",",  mods = "NONE", action = broadcast_send(",") },
	{ key = ".",  mods = "NONE", action = broadcast_send(".") },
	{ key = "/",  mods = "NONE", action = broadcast_send("/") },
	{ key = "`",  mods = "NONE", action = broadcast_send("`") },
	-- Shift+number row
	{ key = "1", mods = "SHIFT", action = broadcast_send("!") },
	{ key = "2", mods = "SHIFT", action = broadcast_send("@") },
	{ key = "3", mods = "SHIFT", action = broadcast_send("#") },
	{ key = "4", mods = "SHIFT", action = broadcast_send("$") },
	{ key = "5", mods = "SHIFT", action = broadcast_send("%") },
	{ key = "6", mods = "SHIFT", action = broadcast_send("^") },
	{ key = "7", mods = "SHIFT", action = broadcast_send("&") },
	{ key = "8", mods = "SHIFT", action = broadcast_send("*") },
	{ key = "9", mods = "SHIFT", action = broadcast_send("(") },
	{ key = "0", mods = "SHIFT", action = broadcast_send(")") },
	-- Shift+special chars
	{ key = "-",  mods = "SHIFT", action = broadcast_send("_") },
	{ key = "=",  mods = "SHIFT", action = broadcast_send("+") },
	{ key = "[",  mods = "SHIFT", action = broadcast_send("{") },
	{ key = "]",  mods = "SHIFT", action = broadcast_send("}") },
	{ key = "\\", mods = "SHIFT", action = broadcast_send("|") },
	{ key = ";",  mods = "SHIFT", action = broadcast_send(":") },
	{ key = "'",  mods = "SHIFT", action = broadcast_send('"') },
	{ key = ",",  mods = "SHIFT", action = broadcast_send("<") },
	{ key = ".",  mods = "SHIFT", action = broadcast_send(">") },
	{ key = "/",  mods = "SHIFT", action = broadcast_send("?") },
	{ key = "`",  mods = "SHIFT", action = broadcast_send("~") },
}
-- Letters a-z (lower and upper)
for b = string.byte("a"), string.byte("z") do
	local c = string.char(b)
	table.insert(broadcast_keys, { key = c, mods = "NONE",  action = broadcast_send(c) })
	table.insert(broadcast_keys, { key = c, mods = "SHIFT", action = broadcast_send(c:upper()) })
end
-- Digits 0-9
for b = string.byte("0"), string.byte("9") do
	table.insert(broadcast_keys, { key = string.char(b), mods = "NONE", action = broadcast_send(string.char(b)) })
end
-- Ctrl+a-z
for b = string.byte("a"), string.byte("z") do
	local c = string.char(b)
	table.insert(broadcast_keys, { key = c, mods = "CTRL", action = broadcast_ctrl(c) })
end

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------
config.keys = {
	-- Reload config
	{ key = "0", mods = "LEADER", action = action.ReloadConfiguration },

	-- Tabs
	{ key = "c", mods = "LEADER", action = action.SpawnTab("DefaultDomain") },
	{ key = "p", mods = "LEADER", action = action.ActivateTabRelative(-1) },
	{ key = "n", mods = "LEADER", action = action.ActivateTabRelative(1) },
	{ key = "x", mods = "LEADER", action = action.CloseCurrentPane({ confirm = true }) },

	-- Move current split to new tab
	{
		key = "!",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			pane:move_to_new_tab()
		end),
	},

	-- Rename tab (pre-filled with current name)
	{
		key = ",",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			local current = window:active_tab():get_title()
			window:perform_action(
				action.PromptInputLine({
					description = "",
					initial_value = current,
					action = wezterm.action_callback(function(win, _, line)
						if line then
							win:active_tab():set_title(line)
						end
					end),
				}),
				pane
			)
		end),
	},

	-- Shift+Backspace / Shift+Space behave as plain Backspace / Space (useful in prompts)
	{ key = "Backspace", mods = "SHIFT", action = action.SendKey({ key = "Backspace", mods = "NONE" }) },
	{ key = "phys:Space", mods = "SHIFT", action = action.SendKey({ key = "Space", mods = "NONE" }) },

	-- Move tab to index (0-based); create missing tabs up to that index
	{
		key = ".",
		mods = "LEADER",
		action = action.PromptInputLine({
			description = "Move tab to new index (0-based)",
			action = wezterm.action_callback(function(window, pane, line)
				local idx = tonumber(line)
				if not idx then
					return
				end
				local ok, tabs = pcall(function()
					return window:tabs()
				end)
				local count = (ok and tabs and #tabs) or 1
				while count <= idx do
					window:perform_action(action.SpawnTab("DefaultDomain"), pane)
					ok, tabs = pcall(function()
						return window:tabs()
					end)
					count = (ok and tabs and #tabs) or (count + 1)
				end
				window:perform_action(action.MoveTab(idx), pane)
			end),
		}),
	},

	-- Splits: h = right (side by side), v = down (top/bottom)
	{ key = "h", mods = "LEADER", action = action.SplitPane({ direction = "Right", size = { Percent = 50 } }) },
	{ key = "j", mods = "LEADER", action = action.SplitPane({ direction = "Right", size = { Percent = 50 } }) },
	{ key = "v", mods = "LEADER", action = action.SplitPane({ direction = "Down", size = { Percent = 50 } }) },
	{ key = "b", mods = "LEADER", action = action.SplitPane({ direction = "Down", size = { Percent = 50 } }) },

	-- Navigate panes (Shift + Arrows) but pass to vim when in vim
	{ key = "LeftArrow", mods = "SHIFT", action = shift_arrow_or_focus("Left", "LeftArrow") },
	{ key = "RightArrow", mods = "SHIFT", action = shift_arrow_or_focus("Right", "RightArrow") },
	{ key = "UpArrow", mods = "SHIFT", action = shift_arrow_or_focus("Up", "UpArrow") },
	{ key = "DownArrow", mods = "SHIFT", action = shift_arrow_or_focus("Down", "DownArrow") },

	-- Resize panes (vim-aware)
	{ key = ",", mods = "ALT", action = alt_or_resize(",", action.AdjustPaneSize({ "Up", 4 })) },
	{ key = ".", mods = "ALT", action = alt_or_resize(".", action.AdjustPaneSize({ "Down", 4 })) },
	{ key = "-", mods = "ALT", action = alt_or_resize("-", action.AdjustPaneSize({ "Left", 5 })) },
	{ key = "=", mods = "ALT", action = alt_or_resize("=", action.AdjustPaneSize({ "Right", 4 })) },

	-- Zoom & swap & rotate
	{ key = "z", mods = "LEADER", action = action.TogglePaneZoomState },
	{ key = "s", mods = "LEADER", action = action.PaneSelect({ mode = "SwapWithActive" }) },
	{ key = "m", mods = "LEADER", action = action.RotatePanes("Clockwise") },
	{ key = "M", mods = "LEADER", action = action.RotatePanes("CounterClockwise") },

	-- Broadcast mode toggle (LEADER+a)
	{
		key = "a",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			wezterm.GLOBAL.broadcast = true
			window:perform_action(
				action.ActivateKeyTable({ name = "broadcast_mode", one_shot = false }),
				pane
			)
			window:toast_notification("Broadcast", "ON", nil, 2000)
		end),
	},

	-- <leader>w → create & switch to a new workspace
	{
		key = "w",
		mods = "LEADER",
		action = action.PromptInputLine({
			description = "Enter new workspace name",
			action = wezterm.action_callback(function(window, pane, line)
				if not line or line == "" then
					return
				end
				mux.spawn_window({ workspace = line })
				mux.set_active_workspace(line)
				window:toast_notification("Workspace", "Created: " .. line, nil, 3000)
			end),
		}),
	},

	-- Alt+w → open built-in workspace switcher (interactive)
	{ key = "w", mods = "ALT", action = action.ShowLauncherArgs({ flags = "WORKSPACES" }) },

	-- LEADER+d → detach (tmux-style Ctrl+a d)
	{
		key = "d",
		mods = "LEADER",
		action = action.Multiple({
			action.SendKey({ key = "a", mods = "CTRL" }),
			action.SendKey({ key = "d" }),
		}),
	},
}

--------------------------------------------------------------------------------
-- Copy mode (vim-like scroll + search)
--------------------------------------------------------------------------------
config.key_tables = {
	broadcast_mode = broadcast_keys,
	copy_mode = {
		-- Movement
		{ key = "h",          mods = "NONE",  action = action.CopyMode("MoveLeft") },
		{ key = "j",          mods = "NONE",  action = action.CopyMode("MoveDown") },
		{ key = "k",          mods = "NONE",  action = action.CopyMode("MoveUp") },
		{ key = "l",          mods = "NONE",  action = action.CopyMode("MoveRight") },
		{ key = "w",          mods = "NONE",  action = action.CopyMode("MoveForwardWord") },
		{ key = "b",          mods = "NONE",  action = action.CopyMode("MoveBackwardWord") },
		{ key = "0",          mods = "NONE",  action = action.CopyMode("MoveToStartOfLine") },
		{ key = "$",          mods = "SHIFT", action = action.CopyMode("MoveToEndOfLineContent") },
		{ key = "g",          mods = "NONE",  action = action.CopyMode("MoveToScrollbackTop") },
		{ key = "G",          mods = "SHIFT", action = action.CopyMode("MoveToScrollbackBottom") },
		{ key = "u",          mods = "CTRL",  action = action.CopyMode({ MoveByPage = -0.5 }) },
		{ key = "d",          mods = "CTRL",  action = action.CopyMode({ MoveByPage = 0.5 }) },
		{ key = "UpArrow",    mods = "NONE",  action = action.CopyMode("MoveUp") },
		{ key = "DownArrow",  mods = "NONE",  action = action.CopyMode("MoveDown") },
		{ key = "LeftArrow",  mods = "NONE",  action = action.CopyMode("MoveLeft") },
		{ key = "RightArrow", mods = "NONE",  action = action.CopyMode("MoveRight") },
		{ key = "PageUp",     mods = "NONE",  action = action.CopyMode({ MoveByPage = -1 }) },
		{ key = "PageDown",   mods = "NONE",  action = action.CopyMode({ MoveByPage = 1 }) },
		-- Search
		{ key = "/",  mods = "NONE",  action = action.Multiple({
			action.Search({ CaseSensitiveString = "" }),
			action.CopyMode("CycleMatchType"), -- cycle CaseSensitive → CaseInsensitive
		}) },
		{ key = "n",  mods = "NONE",  action = action.CopyMode("NextMatch") },
		{ key = "N",  mods = "SHIFT", action = action.CopyMode("PriorMatch") },
		-- Selection
		{ key = "v",  mods = "NONE",  action = action.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "V",  mods = "SHIFT", action = action.CopyMode({ SetSelectionMode = "Line" }) },
		-- Copy and exit
		{ key = "y",     mods = "NONE", action = action.Multiple({
			action.CopyTo("ClipboardAndPrimarySelection"),
			action.CopyMode("Close"),
		}) },
		{ key = "Enter", mods = "NONE", action = action.Multiple({
			action.CopyTo("ClipboardAndPrimarySelection"),
			action.CopyMode("Close"),
		}) },
		-- Exit
		{ key = "q",      mods = "NONE", action = action.CopyMode("Close") },
		{ key = "Escape", mods = "NONE", action = action.CopyMode("Close") },
	},
	search_mode = {
		{ key = "Escape",    mods = "NONE", action = action.CopyMode("Close") },
		{ key = "Enter",     mods = "NONE", action = action.ActivateCopyMode },
		{ key = "/",         mods = "NONE", action = action.CopyMode("ClearPattern") },
		{ key = "UpArrow",   mods = "NONE", action = action.CopyMode("PriorMatch") },
		{ key = "DownArrow", mods = "NONE", action = action.CopyMode("NextMatch") },
		{ key = "n",         mods = "CTRL", action = action.CopyMode("NextMatch") },
		{ key = "p",         mods = "CTRL", action = action.CopyMode("PriorMatch") },
	},
}

-- Mouse scroll: enter copy mode on wheel up (pass through when inside vim)
config.mouse_bindings = {
	{
		event = { Down = { streak = 1, button = { WheelUp = 1 } } },
		mods = "NONE",
		action = wezterm.action_callback(function(window, pane)
			if is_vim(pane) then
				window:perform_action(action.ScrollByCurrentEventWheelDelta, pane)
			else
				window:perform_action(action.ScrollByCurrentEventWheelDelta, pane)
				window:perform_action(action.ActivateCopyMode, pane)
			end
		end),
	},
	{
		event = { Down = { streak = 1, button = { WheelDown = 1 } } },
		mods = "NONE",
		action = wezterm.action_callback(function(window, pane)
			window:perform_action(action.ScrollByCurrentEventWheelDelta, pane)
		end),
	},
}

-- Ctrl+V on Linux: paste via wl-paste, pass through to vim for visual block mode
-- macOS uses WezTerm's default paste behavior
if wezterm.target_triple:find("linux") then
	table.insert(config.keys, {
		key = "v",
		mods = "CTRL",
		action = wezterm.action_callback(function(window, pane)
			if is_vim(pane) then
				window:perform_action(action.SendKey({ key = "v", mods = "CTRL" }), pane)
			else
				local success, stdout = wezterm.run_child_process({ "wl-paste", "--no-newline" })
				if success then
					window:perform_action(action.SendString(stdout), pane)
				end
			end
		end),
	})
end

return config

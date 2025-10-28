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
config.enable_wayland = true

wezterm.on("gui-startup", function(cmd)
	local tab, pane, window = mux.spawn_window(cmd or {})
	window:gui_window():maximize()
end)

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------
if wezterm.target_triple:find("darwin") then
	-- macOS
	config.font_size = 13
elseif wezterm.target_triple:find("linux") then
	-- Linux
	config.font_size = 11
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

-- Workspaces
-- Show current workspace name on right side of status bar
wezterm.on("update-right-status", function(window, pane)
	local name = wezterm.mux.get_active_workspace()

	-- Get current time
	local time = wezterm.strftime("%H:%M:%S")

	window:set_right_status(wezterm.format({
		{ Text = " 󱂬  " .. name .. " | " .. time .. " " },
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
-- Tiny status: show when leader is held (no extra badges)
--------------------------------------------------------------------------------
-- Choose the emoji you want here:
local LEADER_ICON = utf8.char(0x1f7e2) -- green circle

wezterm.on("update-right-status", function(window, _)
	local SOLID_LEFT_ARROW = ""
	local ARROW_FOREGROUND = { Foreground = { Color = "#c6a0f6" } } -- mauve
	local prefix = ""

	if window:leader_is_active() then
		prefix = " " .. LEADER_ICON .. " "
		SOLID_LEFT_ARROW = utf8.char(0xe0b2)
	end

	if window:active_tab():tab_id() ~= 0 then
		ARROW_FOREGROUND = { Foreground = { Color = "#1e2030" } } -- mantle
	end

	window:set_left_status(wezterm.format({
		{ Text = prefix }, -- no background override, inherits bar color
		ARROW_FOREGROUND,
		{ Text = SOLID_LEFT_ARROW },
	}))
end)

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

-- (filters out "default" and any starting with "__")
local function get_custom_workspaces()
	local out = {}
	for _, name in ipairs(mux.get_workspace_names()) do
		if name ~= "default" and not name:match("^__") then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- Show a quick list of custom workspaces (non-interactive)
local function show_custom_workspace_list(window)
	local names = get_custom_workspaces()
	local msg = (#names > 0) and ("Custom workspaces:\n• " .. table.concat(names, "\n• "))
		or "No custom workspaces yet."
	window:toast_notification("WezTerm", msg, nil, 5000)
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

	-- Rename tab (minimal prompt at bottom)
	{
		key = ",",
		mods = "LEADER",
		action = action.PromptInputLine({
			description = "",
			action = wezterm.action_callback(function(window, _, line)
				if line then
					window:active_tab():set_title(line)
				end
			end),
		}),
	},

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

	-- Normal splits (active pane)
	{ key = "j", mods = "LEADER", action = action.SplitPane({ direction = "Right", size = { Percent = 50 } }) },
	{ key = "h", mods = "LEADER", action = action.SplitPane({ direction = "Right", size = { Percent = 50 } }) },

	{ key = "v", mods = "LEADER", action = action.SplitPane({ direction = "Down", size = { Percent = 50 } }) },
	{ key = "b", mods = "LEADER", action = action.SplitPane({ direction = "Down", size = { Percent = 50 } }) },

	-- Navigate panes (Shift + Arrows) but pass to vim when in vim
	{ key = "LeftArrow", mods = "SHIFT", action = shift_arrow_or_focus("Left", "LeftArrow") },
	{ key = "RightArrow", mods = "SHIFT", action = shift_arrow_or_focus("Right", "RightArrow") },
	{ key = "UpArrow", mods = "SHIFT", action = shift_arrow_or_focus("Up", "UpArrow") },
	{ key = "DownArrow", mods = "SHIFT", action = shift_arrow_or_focus("Down", "DownArrow") },

	-- Swap panes (Ctrl+Shift+Arrow) via quick selector
	{ key = "LeftArrow", mods = "CTRL|SHIFT", action = action.PaneSelect({ mode = "SwapWithActive" }) },
	{ key = "RightArrow", mods = "CTRL|SHIFT", action = action.PaneSelect({ mode = "SwapWithActive" }) },
	{ key = "UpArrow", mods = "CTRL|SHIFT", action = action.PaneSelect({ mode = "SwapWithActive" }) },
	{ key = "DownArrow", mods = "CTRL|SHIFT", action = action.PaneSelect({ mode = "SwapWithActive" }) },

	-- Resize panes (vim-aware)
	{ key = ",", mods = "ALT", action = alt_or_resize(",", action.AdjustPaneSize({ "Up", 4 })) },
	{ key = ".", mods = "ALT", action = alt_or_resize(".", action.AdjustPaneSize({ "Down", 4 })) },
	{ key = "-", mods = "ALT", action = alt_or_resize("-", action.AdjustPaneSize({ "Left", 5 })) },
	{ key = "=", mods = "ALT", action = alt_or_resize("=", action.AdjustPaneSize({ "Right", 4 })) },

	-- Zoom & swap
	{ key = "z", mods = "LEADER", action = action.TogglePaneZoomState },
	{ key = "s", mods = "LEADER", action = action.PaneSelect({ mode = "SwapWithActive" }) },

	-- Search: Alt+f or LEADER+f to open search
	{
		key = "f",
		mods = "LEADER",
		action = action.Multiple({
			action.CopyMode("ClearPattern"), -- wipe saved search
			action.Search({ CaseSensitiveString = "" }), -- open empty
		}),
	},
	-- <leader> w → create & switch to a new workspace
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
}

return config

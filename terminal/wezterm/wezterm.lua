local wezterm = require("wezterm")
local act = wezterm.action
local config = {}

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------
config.font_size = 13.0
config.font = wezterm.font("MesloLGS NF", { weight = "Bold" })
config.color_scheme = "Catppuccin Macchiato"
config.audible_bell = "Disabled"

-- Tab bar
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.tab_and_split_indices_are_zero_based = true

-- Leader key (Ctrl+a, tmux-style)
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
-- Tab naming: show only last folder name
--------------------------------------------------------------------------------
wezterm.on("format-tab-title", function(tab)
	local index = tostring(tab.tab_index)
	local title = tab.tab_title

	if title == "" then
		local cwd_uri = tab.active_pane.current_working_dir
		if cwd_uri and cwd_uri.file_path then
			title = cwd_uri.file_path:match("([^/]+)$") or cwd_uri.file_path
		else
			title = "?"
		end
	end

	return " " .. index .. ": " .. title .. " "
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
			window:perform_action(act.SendKey({ key = key, mods = "ALT" }), pane)
		else
			window:perform_action(resize_action, pane)
		end
	end)
end

-- SHIFT+Arrow: pass to vim, else focus wezterm pane
local function shift_arrow_or_focus(dir, keyname)
	return wezterm.action_callback(function(window, pane)
		if is_vim(pane) then
			window:perform_action(act.SendKey({ key = keyname, mods = "SHIFT" }), pane)
		else
			window:perform_action(act.ActivatePaneDirection(dir), pane)
		end
	end)
end

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------
config.keys = {
	-- Reload config
	{ key = "0", mods = "LEADER", action = act.ReloadConfiguration },

	-- Tabs
	{ key = "c", mods = "LEADER", action = act.SpawnTab("DefaultDomain") },
	{ key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) },
	{ key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) },

	-- Rename tab (minimal prompt at bottom)
	{
		key = ",",
		mods = "LEADER",
		action = act.PromptInputLine({
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
		action = act.PromptInputLine({
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
					window:perform_action(act.SpawnTab("DefaultDomain"), pane)
					ok, tabs = pcall(function()
						return window:tabs()
					end)
					count = (ok and tabs and #tabs) or (count + 1)
				end
				window:perform_action(act.MoveTab(idx), pane)
			end),
		}),
	},

	-- Normal splits (active pane)
	{ key = "h", mods = "LEADER", action = act.SplitPane({ direction = "Right", size = { Percent = 50 } }) },
	{ key = "v", mods = "LEADER", action = act.SplitPane({ direction = "Down", size = { Percent = 50 } }) },

	-- Full splits (top-level). Last one you press "wins" the layout.
	{
		key = "j",
		mods = "LEADER",
		action = act.SplitPane({ direction = "Right", size = { Percent = 50 }, top_level = true }),
	},
	{
		key = "b",
		mods = "LEADER",
		action = act.SplitPane({ direction = "Down", size = { Percent = 50 }, top_level = true }),
	},

	-- Navigate panes (Shift + Arrows) but pass to vim when in vim
	{ key = "LeftArrow", mods = "SHIFT", action = shift_arrow_or_focus("Left", "LeftArrow") },
	{ key = "RightArrow", mods = "SHIFT", action = shift_arrow_or_focus("Right", "RightArrow") },
	{ key = "UpArrow", mods = "SHIFT", action = shift_arrow_or_focus("Up", "UpArrow") },
	{ key = "DownArrow", mods = "SHIFT", action = shift_arrow_or_focus("Down", "DownArrow") },

	-- Swap panes (Ctrl+Shift+Arrow) via quick selector
	{ key = "LeftArrow", mods = "CTRL|SHIFT", action = act.PaneSelect({ mode = "SwapWithActive" }) },
	{ key = "RightArrow", mods = "CTRL|SHIFT", action = act.PaneSelect({ mode = "SwapWithActive" }) },
	{ key = "UpArrow", mods = "CTRL|SHIFT", action = act.PaneSelect({ mode = "SwapWithActive" }) },
	{ key = "DownArrow", mods = "CTRL|SHIFT", action = act.PaneSelect({ mode = "SwapWithActive" }) },

	-- Resize panes (vim-aware)
	{ key = ",", mods = "ALT", action = alt_or_resize(",", act.AdjustPaneSize({ "Up", 4 })) },
	{ key = ".", mods = "ALT", action = alt_or_resize(".", act.AdjustPaneSize({ "Down", 4 })) },
	{ key = "-", mods = "ALT", action = alt_or_resize("-", act.AdjustPaneSize({ "Left", 5 })) },
	{ key = "=", mods = "ALT", action = alt_or_resize("=", act.AdjustPaneSize({ "Right", 4 })) },

	-- Zoom & swap
	{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },
	{ key = "S", mods = "LEADER|SHIFT", action = act.PaneSelect({ mode = "SwapWithActive" }) },

	-- Search: Alt+F to open search; n / Shift+n to navigate like Vim
	{ key = "f", mods = "ALT", action = act.Search({ CaseSensitiveString = "" }) },
}

--------------------------------------------------------------------------------
-- Key tables (search mode: n / Shift+n like Neovim)
--------------------------------------------------------------------------------
config.key_tables = config.key_tables or {}
config.key_tables.search_mode = {
	{ key = "n", mods = "NONE", action = act.CopyMode("NextMatch") },
	{ key = "N", mods = "SHIFT", action = act.CopyMode("PriorMatch") },
	{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
	{ key = "Enter", mods = "NONE", action = act.CopyMode("AcceptPattern") },
}

return config

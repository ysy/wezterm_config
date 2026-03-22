local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action

local custom_titles = {}
local leader_state_by_window = {}

local config = wezterm.config_builder()

local function basename(path)
	if not path or path == "" then
		return nil
	end

	return path:gsub("[/\\]+$", ""):match("([^/\\]+)$")
end

local function normalize_process_name(process_name)
	local name = basename(process_name)
	if not name or name == "" then
		return nil
	end

	return name:lower():gsub("%.exe$", "")
end

local function looks_like_managed_title(title)
	if not title or title == "" then
		return false
	end

	if #title > 80 then
		return false
	end

	if title:find("[/\\:]") then
		return false
	end

	return title:match("^[^%s]+%-.+$") ~= nil
end

local function safe_fallback_title(tab)
	local pane = tab.active_pane
	if not pane then
		return "Terminal"
	end

	local process_name = pane.foreground_process_name
	if not process_name and pane.get_foreground_process_name then
		local ok, value = pcall(function()
			return pane:get_foreground_process_name()
		end)
		if ok then
			process_name = value
		end
	end

	return normalize_process_name(process_name) or "Terminal"
end

local function resolved_tab_title(tab)
	local id = tostring(tab.tab_id)
	local title = custom_titles[id]
	if title and title ~= "" then
		return title
	end

	local pane_title = tab.active_pane and tab.active_pane.title or nil
	if looks_like_managed_title(pane_title) then
		return pane_title
	end

	return safe_fallback_title(tab)
end

local function switch_to_english_input()
	pcall(function()
		wezterm.run_child_process({ "im-select.exe", "1033" })
	end)
end

local function copy_mode_escape_action(window, pane)
	local has_selection = false

	pcall(function()
		local text = window:get_selection_text_for_pane(pane)
		has_selection = text ~= nil and text ~= ""
	end)

	if has_selection then
		window:perform_action(act.CopyMode("ClearSelectionMode"), pane)
		return
	end

	window:perform_action(act.CopyMode("Close"), pane)
end

local function workspace_choices()
	local choices = {}
	for _, name in ipairs(mux.get_workspace_names()) do
		table.insert(choices, {
			id = name,
			label = name,
		})
	end

	table.sort(choices, function(a, b)
		return a.label < b.label
	end)

	table.insert(choices, {
		id = "__create_new_workspace__",
		label = "[Create New Session...]",
	})

	return choices
end

local function prompt_for_new_workspace(window, pane)
	window:perform_action(
		act.PromptInputLine({
			description = "Enter name for new session",
			action = wezterm.action_callback(function(inner_window, inner_pane, line)
				if not line or line == "" then
					return
				end

				inner_window:perform_action(
					act.SwitchToWorkspace({
						name = line,
					}),
					inner_pane
				)
			end),
		}),
		pane
	)
end

local function pane_id_from_pane(pane)
	if pane and pane.pane_id then
		return pane:pane_id()
	end

	return nil
end

local function delete_workspace(workspace_name)
	local pane_ids = {}

	for _, mux_window in ipairs(mux.all_windows()) do
		if mux_window:get_workspace() == workspace_name then
			for _, tab in ipairs(mux_window:tabs()) do
				for _, tab_pane in ipairs(tab:panes()) do
					local pane_id = pane_id_from_pane(tab_pane)
					if pane_id then
						table.insert(pane_ids, pane_id)
					end
				end
			end
		end
	end

	for _, pane_id in ipairs(pane_ids) do
		pcall(function()
			wezterm.run_child_process({
				"wezterm",
				"cli",
				"kill-pane",
				"--pane-id",
				tostring(pane_id),
			})
		end)
	end
end

wezterm.on("gui-startup", function(cmd)
	local _, _, window = mux.spawn_window(cmd or {})
	window:gui_window():maximize()
end)

config.default_prog = { "pwsh.exe", "-NoLogo" }
config.color_scheme = "Catppuccin Mocha"
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false
config.status_update_interval = 100
config.font = wezterm.font_with_fallback({
	{ family = "FiraCode Nerd Font", weight = "Regular" },
	"Microsoft YaHei",
})
config.font_size = 11.0

config.mouse_bindings = {
	{ event = { Up = { streak = 1, button = "Left" } }, mods = "NONE", action = act.CompleteSelection("Clipboard") },
	{ event = { Down = { streak = 1, button = "Right" } }, mods = "NONE", action = act.PasteFrom("Clipboard") },
}

wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
	local index = tab.tab_index + 1
	local title = resolved_tab_title(tab)
	title = wezterm.truncate_right(title, math.max(max_width - 4, 1))
	local palette = cfg.resolved_palette.tab_bar

	if tab.is_active then
		return {
			{ Background = { Color = palette.active_tab.bg_color } },
			{ Foreground = { Color = palette.active_tab.fg_color } },
			{ Attribute = { Intensity = "Bold" } },
			{ Text = " [" .. index .. "] " .. title .. " " },
		}
	end

	return {
		{ Background = { Color = palette.inactive_tab.bg_color } },
		{ Foreground = { Color = palette.inactive_tab.fg_color } },
		{ Text = "  " .. index .. ": " .. title .. "  " },
	}
end)

config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
	{
		key = ",",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "Enter new name for tab (empty to reset)",
			action = wezterm.action_callback(function(window, pane, line)
				local tab = window:active_tab()
				local id = tostring(tab:tab_id())
				if line and line ~= "" then
					custom_titles[id] = line
					tab:set_title(line)
				elseif line == "" then
					custom_titles[id] = nil
					tab:set_title("")
				end
			end),
		}),
	},
	{
		key = "s",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			window:perform_action(
				act.InputSelector({
					title = "Choose Session",
					choices = workspace_choices(),
					fuzzy = true,
					fuzzy_description = "Select an existing session or type a new name to create one",
					action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
						local name = id or label
						if not name or name == "" then
							return
						end

						if name == "__create_new_workspace__" then
							prompt_for_new_workspace(inner_window, inner_pane)
							return
						end

						inner_window:perform_action(
							act.SwitchToWorkspace({
								name = name,
							}),
							inner_pane
						)
					end),
				}),
				pane
			)
		end),
	},
	{
		key = "$",
		mods = "LEADER|SHIFT",
		action = act.PromptInputLine({
			description = "Enter new name for current session",
			action = wezterm.action_callback(function(window, pane, line)
				if not line or line == "" then
					return
				end

				local current = window:active_workspace()
				mux.rename_workspace(current, line)
			end),
		}),
	},
	{
		key = "(",
		mods = "LEADER|SHIFT",
		action = act.SwitchWorkspaceRelative(-1),
	},
	{
		key = ")",
		mods = "LEADER|SHIFT",
		action = act.SwitchWorkspaceRelative(1),
	},
	{
		key = ":",
		mods = "LEADER|SHIFT",
		action = act.Confirmation({
			message = "Delete current session/workspace?",
			action = wezterm.action_callback(function(window, pane)
				local current = window:active_workspace()
				if current == "default" then
					window:toast_notification("WezTerm", "Refusing to delete the default workspace", nil, 3000)
					return
				end

				window:perform_action(
					act.SwitchToWorkspace({
						name = "default",
					}),
					pane
				)
				delete_workspace(current)
			end),
		}),
	},
	{ key = "]", mods = "LEADER", action = act.PasteFrom("Clipboard") },
	{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },
	{ key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) },
	{ key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) },
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "r", mods = "LEADER", action = act.ReloadConfiguration },
}

config.key_tables = {
	copy_mode = {
		{ key = "/", mods = "NONE", action = act.Search("CurrentSelectionOrEmptyString") },
		{ key = "n", mods = "NONE", action = act.CopyMode("NextMatch") },
		{ key = "N", mods = "NONE", action = act.CopyMode("PriorMatch") },
		{ key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
		{ key = "^", mods = "SHIFT", action = act.CopyMode("MoveToStartOfLineContent") },
		{ key = "$", mods = "SHIFT", action = act.CopyMode("MoveToEndOfLineContent") },
		{ key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
		{ key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
		{ key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },
		{ key = "H", mods = "SHIFT", action = act.CopyMode("MoveToViewportTop") },
		{ key = "M", mods = "SHIFT", action = act.CopyMode("MoveToViewportMiddle") },
		{ key = "L", mods = "SHIFT", action = act.CopyMode("MoveToViewportBottom") },
		{ key = "o", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEnd") },
		{ key = "Space", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },
		{
			key = "Enter",
			mods = "NONE",
			action = act.Multiple({
				{ CopyTo = "ClipboardAndPrimarySelection" },
				{ CopyMode = "Close" },
			}),
		},
		{
			key = "y",
			mods = "NONE",
			action = act.Multiple({
				{ CopyTo = "ClipboardAndPrimarySelection" },
				{ CopyMode = "Close" },
			}),
		},
		{ key = "u", mods = "NONE", action = act.CopyMode("ClearSelectionMode") },
		{ key = "u", mods = "CTRL", action = act.CopyMode("ClearPattern") },
		{ key = "q", mods = "NONE", action = act.CopyMode("Close") },
		{
			key = "Escape",
			mods = "NONE",
			action = wezterm.action_callback(function(window, pane)
				copy_mode_escape_action(window, pane)
			end),
		},
		{ key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
		{ key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
		{ key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
		{ key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
		{ key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
		{ key = "G", mods = "SHIFT", action = act.CopyMode("MoveToScrollbackBottom") },
	},
	search_mode = {
		{ key = "u", mods = "CTRL", action = act.CopyMode("ClearPattern") },
		{ key = "Enter", mods = "NONE", action = "ActivateCopyMode" },
		{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
		{ key = "n", mods = "CTRL", action = act.CopyMode("NextMatch") },
		{ key = "p", mods = "CTRL", action = act.CopyMode("PriorMatch") },
	},
}

for i = 1, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "LEADER",
		action = act.ActivateTab(i - 1),
	})
end

wezterm.on("window-focus-changed", function(window, pane)
	if window:is_focused() then
		switch_to_english_input()
	end
end)

wezterm.on("update-status", function(window, pane)
	local cells = {}
	local active_key_table = window:active_key_table()
	local workspace = window:active_workspace()
	local palette = window:effective_config().resolved_palette
	local window_id = tostring(window:window_id())
	local leader_is_active = window:leader_is_active()

	if leader_is_active and not leader_state_by_window[window_id] then
		switch_to_english_input()
	end
	leader_state_by_window[window_id] = leader_is_active

	if active_key_table == "copy_mode" then
		table.insert(cells, { Background = { Color = palette.ansi[4] } })
		table.insert(cells, { Foreground = { Color = palette.background } })
		table.insert(cells, { Text = " 󰆏 COPY " })
	elseif active_key_table == "search_mode" then
		table.insert(cells, { Background = { Color = palette.ansi[3] } })
		table.insert(cells, { Foreground = { Color = palette.background } })
		table.insert(cells, { Text = " 󰍉 SEARCH " })
	end

	table.insert(cells, { Background = { Color = "none" } })
	table.insert(cells, { Foreground = { Color = palette.ansi[3] } })
	table.insert(cells, { Text = " 󱂬 " .. workspace .. " " })

	window:set_right_status(wezterm.format(cells))
end)

return config

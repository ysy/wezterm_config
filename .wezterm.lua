local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action

-- 存储手动标题
local custom_titles = {}

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- 1. 启动设置
wezterm.on('gui-startup', function(cmd)
	local _, _, window = mux.spawn_window(cmd or {})
	window:gui_window():maximize()
end)

config.default_prog = { 'pwsh.exe', '-NoLogo' }
config.color_scheme = "Catppuccin Mocha"
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false
config.font = wezterm.font_with_fallback {
	{ family = 'FiraCode Nerd Font', weight = 'Regular' },
	'Microsoft YaHei',
}
config.font_size = 11.0

-- 2. 鼠标
config.mouse_bindings = {
	{ event = { Up = { streak = 1, button = 'Left' } }, mods = 'NONE', action = act.CompleteSelection 'Clipboard' },
	{ event = { Down = { streak = 1, button = 'Right' } }, mods = 'NONE', action = act.PasteFrom 'Clipboard' },
}

-- 3. 样式定制 (恢复原始 Catppuccin Mocha 风格)
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local index = tab.tab_index + 1
	local id = tostring(tab.tab_id)
	
	local title = custom_titles[id] or "Terminal"

	if tab.is_active then
		return {
			{ Background = { Color = "#1e1e2e" } }, -- 激活背景
			{ Foreground = { Color = "#89b4fa" } }, -- 激活文字：蓝色
			{ Text = " [" .. index .. "] " .. title .. " " },
		}
	end
	
	return {
		{ Background = { Color = "#1e1e2e" } }, -- 非激活背景
		{ Foreground = { Color = "#6c7086" } }, -- 非激活文字：灰色
		{ Text = "  " .. index .. ": " .. title .. "  " },
	}
end)

-- 4. 快捷键
config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
	{
		key = ",",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "Enter new name for tab",
			action = wezterm.action_callback(function(window, pane, line)
				if line then
					custom_titles[tostring(window:active_tab():tab_id())] = line
					window:perform_action(act.SetTabTitle(line), pane)
				end
			end),
		}),
	},
	{ key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) },
	{ key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) },
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "r", mods = "LEADER", action = act.ReloadConfiguration },
}

-- 5. 数字键直达
for i = 1, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "LEADER",
		action = act.ActivateTab(i - 1),
	})
end

-- 6. 右侧状态栏
wezterm.on("update-status", function(window, pane)
	local workspace = window:active_workspace()
	window:set_right_status(wezterm.format({
		{ Foreground = { Color = "#a6e3a1" } },
		{ Text = " 󱂬 " .. workspace .. " " },
	}))
end)

return config

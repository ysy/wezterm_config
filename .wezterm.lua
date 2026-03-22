local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action

-- 存储手动标题
local custom_titles = {}

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- ==========================================
-- 1. 基础配置 & 启动最大化
-- ==========================================
wezterm.on("gui-startup", function(cmd)
	local _, _, window = mux.spawn_window(cmd or {})
	window:gui_window():maximize()
end)

config.default_prog = { "pwsh.exe", "-NoLogo" }
config.color_scheme = "Catppuccin Mocha" -- 你可以随时换成别的主题，Tab 颜色会自动跟进
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false
config.font = wezterm.font_with_fallback({
	{ family = "FiraCode Nerd Font", weight = "Regular" },
	"Microsoft YaHei",
})
config.font_size = 11.0

-- ==========================================
-- 2. 鼠标：选中即复制 + 右键粘贴
-- ==========================================
config.mouse_bindings = {
	{ event = { Up = { streak = 1, button = "Left" } }, mods = "NONE", action = act.CompleteSelection("Clipboard") },
	{ event = { Down = { streak = 1, button = "Right" } }, mods = "NONE", action = act.PasteFrom("Clipboard") },
}

-- ==========================================
-- 3. 核心：动态提取主题配色的渲染逻辑
-- ==========================================
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local index = tab.tab_index + 1
	local id = tostring(tab.tab_id)
	local title = custom_titles[id] or "Terminal"

	-- 【核心改动】从当前选中的 color_scheme 中自动提取 Tab 栏配色
	-- 这样你就不需要手动写 #89b4fa 等颜色代码了
	local palette = config.resolved_palette.tab_bar

	if tab.is_active then
		return {
			{ Background = { Color = palette.active_tab.bg_color } },
			{ Foreground = { Color = palette.active_tab.fg_color } },
			{ Attribute = { Intensity = "Bold" } }, -- 激活态加粗，视觉更明显
			{ Text = " [" .. index .. "] " .. title .. " " },
		}
	end

	return {
		{ Background = { Color = palette.inactive_tab.bg_color } },
		{ Foreground = { Color = palette.inactive_tab.fg_color } },
		{ Text = "  " .. index .. ": " .. title .. "  " },
	}
end)

-- ==========================================
-- 4. 快捷键：Leader 键体系
-- ==========================================
config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
	-- 修改标题
	{
		key = ",",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "Enter new name for tab",
			action = wezterm.action_callback(function(window, pane, line)
				if line then
					custom_titles[tostring(window:active_tab():tab_id())] = line
					-- SetTabTitle 虽然在 Windows 下刷新慢，但它能触发重绘信号
					window:perform_action(act.SetTabTitle(line), pane)
				end
			end),
		}),
	},

	-- 【新增】粘贴 (Leader + ])
	{ key = "]", mods = "LEADER", action = act.PasteFrom("Clipboard") },

	-- 进入复制模式 (Leader + [)
	{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },

	-- 基础功能
	{ key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) },
	{ key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) },
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "r", mods = "LEADER", action = act.ReloadConfiguration },
}

-- 数字键直达 (Leader + 1-9)
for i = 1, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "LEADER",
		action = act.ActivateTab(i - 1),
	})
end

-- ==========================================
-- 5. 其他自动化逻辑 (保持稳定)
-- ==========================================
-- 输入法自动切回英文 (im-select)
wezterm.on("window-focus-changed", function(window, pane)
	if window:is_focused() then
		pcall(function()
			wezterm.run_child_process({ "im-select.exe", "1033" })
		end)
	end
end)

-- 状态栏显示 Workspace
wezterm.on("update-status", function(window, pane)
	local workspace = window:active_workspace()
	window:set_right_status(wezterm.format({
		{ Foreground = { Color = "#a6e3a1" } },
		{ Text = " 󱂬 " .. workspace .. " " },
	}))
end)

return config

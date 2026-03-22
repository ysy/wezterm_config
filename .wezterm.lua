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

-- ==========================================
-- 6. 复制模式与搜索模式键位增强
-- ==========================================
config.key_tables = {
	-- 当你按下 Ctrl+B [ 进入的模式
	copy_mode = {
		-- 【1】搜索功能：按下 / 开启搜索
		{ key = "/", mods = "NONE", action = act.Search("CurrentSelectionOrEmptyString") },

		-- 【2】跳转匹配：n 下一个，N 上一个
		{ key = "n", mods = "NONE", action = act.CopyMode("NextMatch") },
		{ key = "N", mods = "NONE", action = act.CopyMode("PriorMatch") },

		-- 【3】选中逻辑：Space 开始选中
		{ key = "Space", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },

		-- 【4】完成复制：Enter 拷贝并自动退出模式
		{
			key = "Enter",
			mods = "NONE",
			action = act.Multiple({
				{ CopyTo = "ClipboardAndPrimarySelection" },
				{ CopyMode = "Close" },
			}),
		},

		-- 按下 Ctrl + u 清空搜索关键字
		{ key = "u", mods = "CTRL", action = act.CopyMode("ClearPattern") },

		-- 退出复制模式
		{ key = "q", mods = "NONE", action = act.CopyMode("Close") },
		{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },

		-- Vim 风格移动 (确保 h j k l 可用)
		{ key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
		{ key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
		{ key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
		{ key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
		{ key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
		{ key = "G", mods = "SHIFT", action = act.CopyMode("MoveToScrollbackBottom") },
	},

	-- 当你按下 / 弹出搜索框后的模式
	search_mode = {
		-- 按下 Ctrl + u 清空搜索关键字
		{ key = "u", mods = "CTRL", action = act.CopyMode("ClearPattern") },
		-- 搜索框里按回车：跳到匹配项并回到复制模式
		{ key = "Enter", mods = "NONE", action = "ActivateCopyMode" },
		-- 搜索框里按 Esc：取消搜索
		{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
		-- 在搜索框里也可以通过 Ctrl+n/p 预览
		{ key = "n", mods = "CTRL", action = act.CopyMode("NextMatch") },
		{ key = "p", mods = "CTRL", action = act.CopyMode("PriorMatch") },
	},
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

-- ==========================================
-- 6. 状态栏：显示模式指示器 + Workspace
-- ==========================================
wezterm.on("update-status", function(window, pane)
	local cells = {}
	local active_key_table = window:active_key_table()
	local workspace = window:active_workspace()

	-- 【核心】获取当前主题已解析的完整色板
	local palette = window:effective_config().resolved_palette

	-- 1. 模式指示器逻辑
	if active_key_table == "copy_mode" then
		-- 使用主题定义的 ANSI 黄色 (通常是 ansi[4])
		table.insert(cells, { Background = { Color = palette.ansi[4] } })
		table.insert(cells, { Foreground = { Color = palette.background } }) -- 文字使用背景色以形成反差
		table.insert(cells, { Text = " 󰆏 COPY " })
	elseif active_key_table == "search_mode" then
		-- 使用主题定义的 ANSI 绿色 (通常是 ansi[3])
		table.insert(cells, { Background = { Color = palette.ansi[3] } })
		table.insert(cells, { Foreground = { Color = palette.background } })
		table.insert(cells, { Text = " 󰍉 SEARCH " })
	end

	-- 2. Workspace 名称
	-- 同样使用主题的绿色作为文字颜色，保持视觉统一
	table.insert(cells, { Background = { Color = "none" } })
	table.insert(cells, { Foreground = { Color = palette.ansi[3] } })
	table.insert(cells, { Text = " 󱂬 " .. workspace .. " " })

	window:set_right_status(wezterm.format(cells))
end)

return config

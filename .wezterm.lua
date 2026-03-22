local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action

-- 存储手动标题
local custom_titles = {}
local pane_title_state = {}

local config = wezterm.config_builder and wezterm.config_builder() or {}

local SHELL_PROCESSES = {
	pwsh = true,
	powershell = true,
	cmd = true,
	bash = true,
	zsh = true,
	fish = true,
	nu = true,
}

local NOISY_CHILD_PROCESSES = {
	rg = true,
	fd = true,
	git = true,
	grep = true,
	findstr = true,
	["lua-language-server"] = true,
	["clangd"] = true,
	["pyright-langserver"] = true,
	node = true,
	lua_language_server = true,
}

local TITLE_PROCESS_PATTERNS = {
	{ pattern = "nvim", name = "nvim" },
	{ pattern = "vim", name = "vim" },
	{ pattern = "hx", name = "hx" },
	{ pattern = "helix", name = "hx" },
	{ pattern = "lazygit", name = "lazygit" },
	{ pattern = "yazi", name = "yazi" },
	{ pattern = "btop", name = "btop" },
	{ pattern = "htop", name = "htop" },
	{ pattern = "less", name = "less" },
	{ pattern = "ssh", name = "ssh" },
	{ pattern = "powershell", name = "pwsh" },
	{ pattern = "pwsh", name = "pwsh" },
	{ pattern = "cmd", name = "cmd" },
}

local PROCESS_ALIASES = {
	powershell = "pwsh",
	pwsh = "pwsh",
	cmd = "cmd",
	bash = "bash",
	nvim = "nvim",
	vim = "vim",
}

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

	name = name:lower():gsub("%.exe$", "")
	name = name:gsub("[^%w%-%._]", "_")
	return PROCESS_ALIASES[name] or name
end

local function uri_to_path(uri)
	if not uri then
		return nil
	end

	if type(uri) == "userdata" or type(uri) == "table" then
		if uri.file_path and uri.file_path ~= "" then
			return uri.file_path
		end
		if uri.path and uri.path ~= "" then
			return uri.path
		end
	end

	local value = tostring(uri)
	value = value:gsub("^file:///", "")
	value = value:gsub("^file://", "")
	value = value:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end)
	return value
end

local function process_info_name(info)
	if not info then
		return nil
	end

	return normalize_process_name(info.executable or info.name)
end

local function first_non_empty(...)
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if value and value ~= "" then
			return value
		end
	end

	return nil
end

local function find_best_process_in_tree(info, depth)
	if not info then
		return nil, -1
	end

	depth = depth or 0
	local best_name = nil
	local best_depth = -1

	for _, child in pairs(info.children or {}) do
		local child_name, child_depth = find_best_process_in_tree(child, depth + 1)
		if child_name and child_depth > best_depth then
			best_name = child_name
			best_depth = child_depth
		end
	end

	local current_name = process_info_name(info)
	if current_name and not NOISY_CHILD_PROCESSES[current_name] and not SHELL_PROCESSES[current_name] then
		if depth >= best_depth then
			return current_name, depth
		end
	end

	return best_name, best_depth
end

local function find_best_cwd_in_tree(info, depth)
	if not info then
		return nil, -1
	end

	depth = depth or 0
	local best_cwd = first_non_empty(info.cwd)
	local best_depth = best_cwd and depth or -1

	for _, child in pairs(info.children or {}) do
		local child_cwd, child_depth = find_best_cwd_in_tree(child, depth + 1)
		if child_cwd and child_depth > best_depth then
			best_cwd = child_cwd
			best_depth = child_depth
		end
	end

	return best_cwd, best_depth
end

local function safe_pane_call(pane, method_name, ...)
	if not pane then
		return nil
	end

	local args = { ... }
	local ok, value = pcall(function()
		return pane[method_name](pane, table.unpack(args))
	end)
	if ok then
		return value
	end

	return nil
end

local function current_dir_name(pane)
	local cwd_uri = safe_pane_call(pane, "get_current_working_dir")
	local cwd = uri_to_path(cwd_uri)
	local info = safe_pane_call(pane, "get_foreground_process_info")
	if (not cwd or cwd == "") and info then
		local proc_cwd = select(1, find_best_cwd_in_tree(info))
		cwd = proc_cwd
	end
	if not cwd or cwd == "" then
		return "?"
	end

	cwd = cwd:gsub("[/\\]+$", "")
	return cwd:match("([^/\\]+)$") or cwd
end

local function process_from_title(title)
	if not title or title == "" then
		return nil
	end

	local lowered = title:lower()
	for _, item in ipairs(TITLE_PROCESS_PATTERNS) do
		if lowered:find(item.pattern, 1, true) then
			return item.name
		end
	end

	return nil
end

local function get_tab_id(tab)
	return tostring(tab:tab_id())
end

local function resolve_program_name(pane)
	local pane_id = tostring(safe_pane_call(pane, "pane_id") or "unknown")
	local state = pane_title_state[pane_id] or {}
	local info = safe_pane_call(pane, "get_foreground_process_info")
	local foreground = normalize_process_name(safe_pane_call(pane, "get_foreground_process_name"))
	local title_program = process_from_title(safe_pane_call(pane, "get_title"))
	local is_alt_screen = safe_pane_call(pane, "is_alt_screen_active")
	local tree_program = select(1, find_best_process_in_tree(info))

	local program = tree_program or foreground

	-- alt screen 下优先相信 TUI 程序自己设置的 title；
	-- 对噪声子进程保持上一个稳定的主程序名，避免 nvim 被 LSP/rg 覆盖。
	if is_alt_screen and title_program and not NOISY_CHILD_PROCESSES[title_program] then
		program = title_program
	elseif is_alt_screen and state.program and not SHELL_PROCESSES[state.program] then
		program = state.program
	elseif foreground and NOISY_CHILD_PROCESSES[foreground] and state.program and not SHELL_PROCESSES[state.program] then
		program = state.program
	elseif title_program and not NOISY_CHILD_PROCESSES[title_program] and not SHELL_PROCESSES[foreground or ""] then
		program = title_program
	end

	program = program or state.program or "shell"
	state.program = program
	pane_title_state[pane_id] = state

	return program
end

local function dynamic_tab_title_from_pane(pane)
	if not pane then
		return "Terminal"
	end

	local program = resolve_program_name(pane)
	local dir = current_dir_name(pane)
	return string.format("%s-%s", program, dir)
end

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
config.status_update_interval = 200
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
	local title = custom_titles[id]
	if not title or title == "" then
		title = tab.tab_title
	end
	if not title or title == "" then
		title = tab.active_pane.title
	end
	title = wezterm.truncate_right(title, math.max(max_width - 4, 1))

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
			description = "Enter new name for tab (empty to reset)",
			action = wezterm.action_callback(function(window, pane, line)
				local active_tab = window:mux_window():active_tab()
				local active_tab_id = get_tab_id(active_tab)
				if line and line ~= "" then
					custom_titles[active_tab_id] = line
					active_tab:set_title(line)
				elseif line == "" then
					custom_titles[active_tab_id] = nil
					active_tab:set_title(dynamic_tab_title_from_pane(pane))
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
	local tab = window:mux_window():active_tab()
	local tab_id = get_tab_id(tab)

	-- 【核心】获取当前主题已解析的完整色板
	local palette = window:effective_config().resolved_palette

	if tab and not custom_titles[tab_id] then
		local title = dynamic_tab_title_from_pane(pane)
		if tab:get_title() ~= title then
			tab:set_title(title)
		end
	end

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

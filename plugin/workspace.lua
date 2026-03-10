local wezterm = require("wezterm")
local fs = require('fs')
local win_mod = require('window')
local utils = require('utils')

local pub = {}

--- Checks if the user is on windows
local is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"

--- Retrieves the current workspace data from the active window.
-- @param window wezterm.Window: The active window to retrieve the workspace data from.
-- @return table or nil: The workspace data table or nil if no active window is found.
function pub.retrieve_workspace_data(window)
	local workspace_name = window:active_workspace()
	local workspace_data = {
		name = workspace_name,
		last_modified = os.time(),
		windows = {},
	}

	-- Iterale over windows
	for _, mux_win in ipairs(wezterm.mux.all_windows()) do
		if mux_win:get_workspace() == workspace_name then
			if mux_win:gui_window() then -- Check if it has a gui window
				local win_data = win_mod.retrieve_window_data(mux_win)
				table.insert(workspace_data.windows, win_data)
			else
				wezterm.log_info("Skipping non-gui window with id: " .. tostring(mux_win:window_id()))
			end
		end
	end

	return workspace_data
end

--- Recreates the workspace based on the provided data.
-- @param window wezterm.Window: The active window to recreate the workspace in.
-- @param workspace_name string: The name of the workspace to recreate.
-- @param workspace_data table: The data structure containing the saved workspace state.
-- @return boolean|nil, table: Success flag, and list of git branch mismatches.
function pub.recreate_workspace(window, workspace_name, workspace_data)
    if not workspace_data or not workspace_data.windows then
        wezterm.log_info("Invalid or empty workspace data provided.")
        return nil, {}
    end

    local tabs = window:mux_window():tabs()

    if #tabs ~= 1 or #tabs[1]:panes() ~= 1 then
        wezterm.log_info("Restoration can only be performed in a window with a single tab and a single pane")
        utils.notify(window, 'Restoration can only be performed in a window with a single tab and a single pane')
        return nil, {}
    end

    local all_mismatches = {}

    -- Recreate windows tabs and panes from the saved state
    for idx, win_data in ipairs(workspace_data.windows) do
        local mismatches
        if idx == 1 then
            -- The first window will be restored in the current window
            mismatches = win_mod.restore_window(window, win_data)
        else
            -- All other windows will be spawned in a new window
            local _, _, w = wezterm.mux.spawn_window({
                workspace = workspace_name,
            })
            mismatches = win_mod.restore_window(w:gui_window(), win_data)
        end
        if mismatches then
            for _, m in ipairs(mismatches) do
                table.insert(all_mismatches, m)
            end
        end
    end

    wezterm.log_info("Workspace recreated with new tabs and panes based on saved state.")
    return true, all_mismatches
end

--- Restores a workspace name
--- @return table: List of git branch mismatches detected during restore.
function pub.restore_workspace(window, dir, workspace_name)
    wezterm.log_info("Restoring state for workspace: " .. workspace_name)
    local file_path = dir .. "wezterm_state_" .. fs.escape_file_name(workspace_name) .. ".json"

    local workspace_data = fs.load_from_json_file(file_path)
    if not workspace_data then
        utils.notify(window, 'Workspace state file not found for workspace: ' .. workspace_name)
        return {}
    end

    local success, mismatches = pub.recreate_workspace(window, workspace_name, workspace_data)
    if not success then
        utils.notify(window, 'Workspace state loading failed for workspace: ' .. workspace_name)
    end

    return success, mismatches or {}
end

--- Extracts the short directory name from a cwd URI.
--- @param cwd string|nil
--- @return string
local function short_cwd(cwd)
	if not cwd or cwd == "" then
		return ""
	end
	-- strip file://hostname prefix, take last path component
	local path = cwd:gsub("file://[^/]*", "")
	-- url decode
	path = path:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end)
	-- get last component
	local name = path:match("([^/\\]+)$") or path
	return name
end

--- Extracts the short process name from a tty string.
--- @param tty string|nil
--- @return string
local function short_process(tty)
	if not tty or tty == "" or tty == "nil" then
		return ""
	end
	-- get filename from full path
	local name = tty:match("([^/\\]+)$") or tty
	-- remove leading '-' for login shells
	name = name:gsub("^-", "")
	-- trim whitespace
	name = name:match("^%s*(.-)%s*$") or name
	return name
end

--- Builds a compact tab summary string like "nvim@myproject[main]"
--- @param tab table: The tab data.
--- @return string
local function build_tab_summary(tab)
	local num_panes = tab.panes and #tab.panes or 0
	-- Find the active pane, fallback to first
	local active_pane = nil
	if tab.panes then
		for _, p in ipairs(tab.panes) do
			if p.is_active then
				active_pane = p
				break
			end
		end
		active_pane = active_pane or tab.panes[1]
	end
	if not active_pane then
		return tab.title or "tab"
	end

	local proc = short_process(active_pane.tty)
	local cwd = short_cwd(active_pane.cwd)
	local branch = active_pane.git_branch

	-- Build: "proc@cwd[branch](panes)" — each part optional
	local result = ""
	if proc ~= "" then
		result = proc
	end
	if cwd ~= "" then
		result = result ~= "" and (result .. "@" .. cwd) or cwd
	end
	if branch then
		result = result .. "[" .. branch .. "]"
	end
	if num_panes > 1 then
		result = result .. "(" .. num_panes .. "p)"
	end

	return result ~= "" and result or (tab.title or "tab")
end

--- Builds a rich label for a workspace entry in the selection list.
--- @param data table: The workspace data loaded from JSON.
--- @return string
function pub.build_workspace_label(data)
	local num_windows = data.windows and #data.windows or 0
	local num_tabs = 0
	local tab_summaries = {}

	if data.windows then
		for _, w in ipairs(data.windows) do
			if w.tabs then
				num_tabs = num_tabs + #w.tabs
				for _, t in ipairs(w.tabs) do
					table.insert(tab_summaries, build_tab_summary(t))
				end
			end
		end
	end

	local time_str = ""
	if data.last_modified then
		time_str = os.date("%Y-%m-%d %H:%M", data.last_modified)
	end

	local tabs_str = ""
	if #tab_summaries > 0 then
		tabs_str = "  " .. table.concat(tab_summaries, " | ")
	end

	return string.format(
		"%-20s  [W:%d T:%d]  %s%s",
		data.name, num_windows, num_tabs, time_str, tabs_str
	)
end

--- Returns the list of available workspaces
--- @param dir string
--- @return table
function pub.get_workspaces(dir)
	local choices = {}
	local success, files = pcall(wezterm.read_dir, dir)

	if success then
		for _, full_path in ipairs(files) do
			local filename = full_path:match("([^/\\]+)$")
			if filename and filename:find("wezterm_state_") and filename:find("%.json$") then
				local data = fs.load_from_json_file(full_path)
				if data then
					local rich_label = pub.build_workspace_label(data)
					table.insert(choices, { id = data.name, label = rich_label })
				end
			end
		end
	else
		-- Fallback to ls for older wezterm versions or if read_dir fails
		for d in io.popen("ls -pa " .. dir .. " | grep -v /"):lines() do
			if string.find(d, "wezterm_state_") then
				local w = d:gsub("wezterm_state_", "")
				w = w:gsub(".json", "")
				table.insert(choices, { id = fs.unescape_file_name(w), label = fs.unescape_file_name(w) })
			end
		end
	end
	
    table.sort(choices, function(a, b)
        return a.id < b.id
    end)

	return choices
end

return pub

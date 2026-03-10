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

--- Builds a summary string for a single pane.
--- @param pane table: The pane data.
--- @return string
local function build_pane_summary(pane)
	local parts = {}
	local cwd = short_cwd(pane.cwd)
	local proc = short_process(pane.tty)
	if cwd ~= "" then
		table.insert(parts, "\u{f07c} " .. cwd)
	end
	if proc ~= "" then
		table.insert(parts, "\u{f120} " .. proc)
	end
	if pane.git_branch then
		table.insert(parts, "\u{e0a0} " .. pane.git_branch)
	end
	return table.concat(parts, "  ")
end

--- Builds a compact tab summary showing all panes (active first).
--- @param tab table: The tab data.
--- @return string
local function build_tab_summary(tab)
	if not tab.panes or #tab.panes == 0 then
		return tab.title or "tab"
	end

	-- Sort: active pane first, then the rest in order
	local active = nil
	local others = {}
	for _, p in ipairs(tab.panes) do
		if p.is_active then
			active = p
		else
			table.insert(others, p)
		end
	end
	active = active or tab.panes[1]

	local result = build_pane_summary(active)

	for _, p in ipairs(others) do
		local summary = build_pane_summary(p)
		if summary ~= "" then
			result = result .. " | " .. summary
		end
	end

	return result ~= "" and result or (tab.title or "tab")
end

--- Counts total windows and tabs in workspace data.
--- @param data table: The workspace data loaded from JSON.
--- @return number, number
local function count_windows_tabs(data)
	local num_windows = 0
	local num_tabs = 0
	if data.windows then
		num_windows = #data.windows
		for _, w in ipairs(data.windows) do
			if w.tabs then
				num_tabs = num_tabs + #w.tabs
			end
		end
	end
	return num_windows, num_tabs
end

--- Builds a rich label for a workspace entry in the selection list.
--- @param data table: The workspace data loaded from JSON.
--- @return string
function pub.build_workspace_label(data)
	local time_str = ""
	if data.last_modified then
		time_str = os.date("%Y-%m-%d %H:%M", data.last_modified)
	end

	local num_windows, num_tabs = count_windows_tabs(data)
	local counts = string.format(
		"%d %s, %d %s",
		num_windows, num_windows == 1 and "window" or "windows",
		num_tabs, num_tabs == 1 and "tab" or "tabs"
	)

	local label = data.name
	if time_str ~= "" then
		label = label .. " - " .. time_str
	end
	label = label .. " (" .. counts .. ")"
	return label
end

--- Restores a single tab from a saved session into the current window.
--- @param window any: The active window.
--- @param dir string: The state directory.
--- @param workspace_name string: The workspace name.
--- @param win_idx number: The window index (1-based).
--- @param tab_idx number: The tab index (1-based).
--- @return table: List of git branch mismatches.
function pub.restore_single_tab(window, dir, workspace_name, win_idx, tab_idx)
	local tab_mod = require("tab")
	local file_path = dir .. "wezterm_state_" .. fs.escape_file_name(workspace_name) .. ".json"
	local workspace_data = fs.load_from_json_file(file_path)
	if not workspace_data then
		utils.notify(window, "Session file not found for: " .. workspace_name)
		return {}
	end

	local win_data = workspace_data.windows and workspace_data.windows[win_idx]
	if not win_data then
		utils.notify(window, "Window not found in session")
		return {}
	end

	local tab_data = win_data.tabs and win_data.tabs[tab_idx]
	if not tab_data then
		utils.notify(window, "Tab not found in session")
		return {}
	end

	local tab, mismatches = tab_mod.restore_tab(window, tab_data)
	if tab then
		tab:activate()
	end
	return mismatches or {}
end

--- Returns the list of available workspaces (compact, one row per workspace).
--- Used by delete and edit flows.
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

--- Returns a detailed list of workspaces with one header row per workspace
--- and one indented row per tab. Header rows have id = workspace name,
--- tab rows have id = "workspace_name::tab::win_idx::tab_idx".
--- @param dir string
--- @return table
function pub.get_workspaces_detailed(dir)
	local choices = {}
	local success, files = pcall(wezterm.read_dir, dir)

	if success then
		-- Collect and sort workspace data
		local workspaces = {}
		for _, full_path in ipairs(files) do
			local filename = full_path:match("([^/\\]+)$")
			if filename and filename:find("wezterm_state_") and filename:find("%.json$") then
				local data = fs.load_from_json_file(full_path)
				if data then
					table.insert(workspaces, data)
				end
			end
		end
		table.sort(workspaces, function(a, b) return a.name < b.name end)

		for _, data in ipairs(workspaces) do
			-- Header row
			local rich_label = pub.build_workspace_label(data)
			table.insert(choices, { id = data.name, label = rich_label })

			-- Tab detail rows
			if data.windows then
				for wi, w in ipairs(data.windows) do
					if w.tabs then
						for ti, t in ipairs(w.tabs) do
							local tab_id = data.name .. "::tab::" .. wi .. "::" .. ti
							local summary = build_tab_summary(t)
							local tab_label = "  \u{f2d0} " .. wi .. "  " .. summary
							table.insert(choices, { id = tab_id, label = tab_label })
						end
					end
				end
			end
		end
	else
		-- Fallback: no detail, same as get_workspaces
		return pub.get_workspaces(dir)
	end

	return choices
end

--- Returns the tab-level choices for a specific workspace.
--- First entry is "Load entire workspace", followed by individual tab rows.
--- @param dir string
--- @param workspace_name string
--- @return table
function pub.get_workspace_tabs(dir, workspace_name)
	local choices = {}
	local file_path = dir .. "wezterm_state_" .. fs.escape_file_name(workspace_name) .. ".json"
	local data = fs.load_from_json_file(file_path)
	if not data then
		return choices
	end

	-- First option: load the entire workspace
	table.insert(choices, {
		id = workspace_name,
		label = "\u{f0e8} Load entire workspace: " .. workspace_name,
	})

	-- Individual tab rows
	if data.windows then
		for wi, w in ipairs(data.windows) do
			if w.tabs then
				for ti, t in ipairs(w.tabs) do
					local tab_id = workspace_name .. "::tab::" .. wi .. "::" .. ti
					local summary = build_tab_summary(t)
					local tab_label = "\u{f2d0} " .. wi .. "  " .. summary
					table.insert(choices, { id = tab_id, label = tab_label })
				end
			end
		end
	end

	return choices
end

return pub

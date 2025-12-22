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
function pub.recreate_workspace(window, workspace_name, workspace_data)
    if not workspace_data or not workspace_data.windows then
        wezterm.log_info("Invalid or empty workspace data provided.")
        return
    end

    local tabs = window:mux_window():tabs()

    if #tabs ~= 1 or #tabs[1]:panes() ~= 1 then
        wezterm.log_info("Restoration can only be performed in a window with a single tab and a single pane")
        utils.notify(window, 'Restoration can only be performed in a window with a single tab and a single pane')
        return
    end

    -- Recreate windows tabs and panes from the saved state
    for idx, win_data in ipairs(workspace_data.windows) do
        if idx == 1 then
            -- The first window will be restored in the current window
            win_mod.restore_window(window, win_data)
        else
            -- All other windows will be spawned in a new window
            local _, _, w = wezterm.mux.spawn_window({
                workspace = workspace_name,
            })
            win_mod.restore_window(w:gui_window(), win_data)
        end
    end

    wezterm.log_info("Workspace recreated with new tabs and panes based on saved state.")
    return true
end

--- Restores a workspace name
function pub.restore_workspace(window, dir, workspace_name)
    wezterm.log_info("Restoring state for workspace: " .. workspace_name)
    local file_path = dir .. "wezterm_state_" .. fs.escape_file_name(workspace_name) .. ".json"

    local workspace_data = fs.load_from_json_file(file_path)
    if not workspace_data then
        utils.notify(window, 'Workspace state file not found for workspace: ' .. workspace_name)
        return
    end

    if pub.recreate_workspace(window, workspace_name, workspace_data) then
        utils.notify(window, 'Workspace state loaded for workspace: ' .. workspace_name)
    else
        utils.notify(window, 'Workspace state loading failed for workspace: ' .. workspace_name)
    end
end

--- Returns the list of available workspaces
--- @param dir string
--- @return table
function pub.get_workspaces(dir)
    local choices = {}
    for d in io.popen("ls -pa " .. dir .. " | grep -v /"):lines() do
        if string.find(d, "wezterm_state_") then
            local w = d:gsub("wezterm_state_", "")
            w = w:gsub(".json", "")
            table.insert(choices, { id = d, label = fs.unescape_file_name(w) })
        end
    end
    return choices
end

return pub

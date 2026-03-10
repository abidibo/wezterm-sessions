local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action

---@class public_module
local pub = {}

--- wezterm plugin directory
local plugin_dir

--- checks if the user is on windows
local is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"
local separator = is_windows and "\\" or "/"

--- Checks if the plugin directory exists
--- @return boolean
local function directory_exists(path)
	local success, result = pcall(wezterm.read_dir, plugin_dir .. path)
	return success and result
end

--- Returns the name of the package, used when requiring modules
--- @return string
local function get_require_path()
	local path1 = "httpssCssZssZsgithubsDscomsZsabidibosZswezterm-sessions"
	local path2 = "httpssCssZssZsgithubsDscomsZsabidibosZswezterm-sessionsZs"
	return directory_exists(path2) and path2 or path1
end

--- Adds the wezterm plugin directory to the lua path
local function enable_sub_modules()
	plugin_dir = wezterm.plugin.list()[1].plugin_dir:gsub(separator .. "[^" .. separator .. "]*$", "")
	package.path = package.path
		.. ";"
		.. plugin_dir
		.. separator
		.. get_require_path()
		.. separator
		.. "plugin"
		.. separator
		.. "?.lua"
end
enable_sub_modules()

--- Now we can import local stuff
local ws_mod = require("workspace")
local fs_mod = require("fs")
local timer_mod = require("timer")

--- The directory where we store the workspaces state
local save_state_dir = plugin_dir .. separator .. get_require_path() .. separator .. "state" .. separator

--- Deduplicates git branch mismatches by repo, keeping unique repo entries.
--- @param mismatches table
--- @return table
local function dedupe_mismatches(mismatches)
	local seen = {}
	local result = {}
	for _, m in ipairs(mismatches) do
		local key = (m.repo or "") .. ":" .. (m.saved_branch or "") .. ":" .. (m.current_branch or "")
		if not seen[key] then
			seen[key] = true
			table.insert(result, m)
		end
	end
	return result
end

--- Formats a git branch mismatch notification message.
--- @param mismatches table
--- @return string
local function format_mismatch_message(mismatches)
	local lines = { "Git branch changed since last save:" }
	for _, m in ipairs(mismatches) do
		local repo_name = m.repo and m.repo:match("([^/\\]+)$") or "unknown"
		table.insert(lines, string.format(
			"  %s: %s -> %s",
			repo_name, m.saved_branch, m.current_branch
		))
	end
	return table.concat(lines, "\n")
end

--- Loads the saved json file matching the current workspace.
function pub.restore_state(window)
	local workspace_name = window:active_workspace()
	wezterm.emit("wezterm-sessions.restore.start", workspace_name)
	local success, mismatches = ws_mod.restore_workspace(window, save_state_dir, workspace_name)
	wezterm.emit("wezterm-sessions.restore.end", workspace_name)

	if not success then
		return
	end

	-- Build a single notification combining restore success + git warnings
	local config = pub.config or DEFAULTS
	local msg = "Workspace state loaded for: " .. workspace_name .. "."
	local duration = 4000

	if config.git_branch_warn and mismatches and #mismatches > 0 then
		local deduped = dedupe_mismatches(mismatches)
		if #deduped > 0 then
			msg = msg .. " " .. format_mismatch_message(deduped)
			duration = 8000
			wezterm.emit("wezterm-sessions.git.branch_mismatch", workspace_name, deduped)
		end
	end

	window:toast_notification("WezTerm Sessions", msg, nil, duration)
end

--- Allows to select which workspace to load
function pub.load_state(window, pane)
	local choices = ws_mod.get_workspaces(save_state_dir)

	window:perform_action(
		act.InputSelector({
			action = wezterm.action_callback(function(_, inner_pane, id, label)
				if id and label then
					wezterm.emit("wezterm-sessions.load.start", id)
					wezterm.log_info("Switching to ws: " .. id)
					-- switch to workspace
					window:perform_action(
						act.SwitchToWorkspace({
							name = id,
						}),
						inner_pane
					)
					-- we need to wait for the switch to complete
					wezterm.sleep_ms(2000)
					window:perform_action(act.EmitEvent("wezter-sessions-switch"), pane)
				end
			end),
			title = "Choose Workspace",
			description = "Select a workspace and press Enter = accept, Esc = cancel, / = filter",
			fuzzy_description = "Workspace to switch: ",
			choices = choices,
			fuzzy = true,
		}),
		pane
	)
end

--- After the workspace switch is complete we restore the workspace
wezterm.on("wezter-sessions-switch", function(window, _)
	local workspace_name = window:active_workspace()
	pub.restore_state(window)
	wezterm.emit("wezterm-sessions.load.end", workspace_name)
end)

--- Orchestrator function to save the current workspace state.
-- Collects workspace data, saves it to a JSON file, and displays a notification.
function pub.save_state(window, notify)
	local data = ws_mod.retrieve_workspace_data(window)

	-- Construct the file path based on the workspace name
	local file_path = save_state_dir .. "wezterm_state_" .. fs_mod.escape_file_name(data.name) .. ".json"
	wezterm.emit("wezterm-sessions.save.start", file_path)

	-- Save the workspace data to a JSON file and display the appropriate notification
	local res = fs_mod.save_to_json_file(data, file_path)
	if notify then
		if res then
			window:toast_notification("WezTerm Sessions", "Workspace state saved successfully", nil, 4000)
		else
			window:toast_notification("WezTerm Sessions", "Failed to save workspace state", nil, 4000)
		end
	end
	wezterm.emit("wezterm-sessions.save.end", file_path, res)
end

--- Allows to select which workspace to delete
function pub.delete_state(window, pane)
	local choices = ws_mod.get_workspaces(save_state_dir)

	window:perform_action(
		act.InputSelector({
			action = wezterm.action_callback(function(_, _, id, label)
				if id and label then
					wezterm.log_info("Deleting ws: " .. id)
					local file_path = save_state_dir .. "wezterm_state_" .. fs_mod.escape_file_name(id) .. ".json"
					wezterm.emit("wezterm-sessions.delete.start", file_path)

					local res = fs_mod.delete_json_file(file_path)
					if res then
						window:toast_notification("WezTerm Sessions", "Workspace state deleted successfully", nil, 4000)
					else
						window:toast_notification("WezTerm Sessions", "Failed to delete workspace state", nil, 4000)
					end
					wezterm.emit("wezterm-sessions.delete.end", file_path, res)
				end
			end),
			title = "Choose Workspace to delete",
			description = "Select a workspace and press Enter = accept, Esc = cancel, / = filter",
			fuzzy_description = "Workspace to delete: ",
			choices = choices,
			fuzzy = true,
		}),
		pane
	)
end

--- Allows to select which workspace state to edit in favourite editor
function pub.edit_state(window, pane)
	local choices = ws_mod.get_workspaces(save_state_dir)

	window:perform_action(
		act.InputSelector({
			action = wezterm.action_callback(function(_, inner_pane, id, label)
				if id and label then
					wezterm.log_info("Editing ws: " .. id)
					local file_path = save_state_dir .. "wezterm_state_" .. fs_mod.escape_file_name(id) .. ".json"
					local editor = os.getenv("EDITOR")
					if not editor then
						editor = "nvim"
					end
					wezterm.emit("wezterm-sessions.edit.start", file_path, editor)
					local command = string.format("%s %s\n", editor, file_path)
					inner_pane:send_text(command)
				end
			end),
			title = "Choose Workspace state to edit",
			description = "Select a workspace and press Enter = accept, Esc = cancel, / = filter",
			fuzzy_description = "Workspace to edit: ",
			choices = choices,
			fuzzy = true,
		}),
		pane
	)
end

--- Forks the current session into a new one
function pub.fork_state(window, pane)
	window:perform_action(
		act.PromptInputLine({
			description = "Enter name for the forked workspace:",
			action = wezterm.action_callback(function(inner_window, _, line)
				if not line then
					return
				end
				local new_workspace_name = line

				wezterm.log_info("Forking workspace to: " .. new_workspace_name)

				local data = ws_mod.retrieve_workspace_data(inner_window)

				local _, _, w = wezterm.mux.spawn_window({
					workspace = new_workspace_name,
				})

				mux.set_active_workspace(new_workspace_name)

				ws_mod.recreate_workspace(w:gui_window(), new_workspace_name, data)

				data.name = new_workspace_name
				local file_path = save_state_dir
					.. "wezterm_state_"
					.. fs_mod.escape_file_name(new_workspace_name)
					.. ".json"
				fs_mod.save_to_json_file(data, file_path)

				inner_window:toast_notification(
					"WezTerm Sessions",
					"Workspace forked successfully to " .. new_workspace_name,
					nil,
					4000
				)
			end),
		}),
		pane
	)
end

-- Autosaving stuff

local auto_save_timer

-- Start autosave
function pub.start_autosave(window)
	local interval = pub.config.auto_save_interval_s
	auto_save_timer = timer_mod.set_interval(function()
		pub.save_state(window, false)
	end, interval)
	window:toast_notification("WezTerm Sessions", "Auto save enabled", nil, 2000)
end

-- Stop autosave
function pub.stop_autosave(window)
	if auto_save_timer then
		auto_save_timer()
		auto_save_timer = nil
		window:toast_notification("WezTerm Sessions", "Auto save disabled", nil, 2000)
	end
end

-- Toggle autosave
function pub.toggle_autosave(window)
	if auto_save_timer then
		pub.stop_autosave(window)
	else
		pub.start_autosave(window)
	end
end

local DEFAULTS = {
	auto_save_interval_s = 30,
	git_branch_warn = true,
}

---Sets default keybindings
function pub.apply_to_config(config, user_config)
	config = config or {}
	config.keys = config.keys or {}

	user_config = user_config or {}

	pub.config = {
		auto_save_interval_s = user_config.auto_save_interval_s or DEFAULTS.auto_save_interval_s,
		git_branch_warn = user_config.git_branch_warn ~= nil and user_config.git_branch_warn or DEFAULTS.git_branch_warn,
	}

	table.insert(config.keys, {
		key = "s",
		mods = "ALT",
		action = act({ EmitEvent = "save_session" }),
	})
	table.insert(config.keys, {
		key = "l",
		mods = "ALT",
		action = act({ EmitEvent = "load_session" }),
	})
	table.insert(config.keys, {
		key = "r",
		mods = "ALT",
		action = act({ EmitEvent = "restore_session" }),
	})
	table.insert(config.keys, {
		key = "d",
		mods = "CTRL|SHIFT",
		action = act({ EmitEvent = "delete_session" }),
	})
	table.insert(config.keys, {
		key = "e",
		mods = "CTRL|SHIFT",
		action = act({ EmitEvent = "edit_session" }),
	})
	table.insert(config.keys, {
		key = "a",
		mods = "ALT",
		action = act({ EmitEvent = "toggle_autosave" }),
	})
	table.insert(config.keys, {
		key = "f",
		mods = "ALT",
		action = act({ EmitEvent = "fork_session" }),
	})
end

--- Event handlers
wezterm.on("save_session", function(window)
	pub.save_state(window, true)
end)
wezterm.on("load_session", function(window, pane)
	pub.load_state(window, pane)
end)
wezterm.on("restore_session", function(window)
	pub.restore_state(window)
end)
wezterm.on("delete_session", function(window, pane)
	pub.delete_state(window, pane)
end)
wezterm.on("edit_session", function(window, pane)
	pub.edit_state(window, pane)
end)
wezterm.on("fork_session", function(window, pane)
	pub.fork_state(window, pane)
end)
wezterm.on("toggle_autosave", function(window)
	pub.toggle_autosave(window)
end)

return pub

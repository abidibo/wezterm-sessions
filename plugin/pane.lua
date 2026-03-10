local wezterm = require("wezterm")
local fs = require("fs")
local git = require("git")
local pub = {}

--- Retrieve pane data
-- @param pane_info table: The pane information table.
-- @return table: The pane data table.
function pub.retrieve_pane_data(pane_info)
	wezterm.log_info(
		pane_info,
		pane_info.pane:get_foreground_process_name(),
		pane_info.pane:get_foreground_process_info()
	)

	-- default command line from process name
	local tty = tostring(pane_info.pane:get_foreground_process_name())
	-- we try to read process infoo in cmdline proc file to get the full command
	local success, pinfo = pcall(function()
		return pane_info.pane:get_foreground_process_info()
	end)
	if success and pinfo ~= nil then
		local cmdline_path = "/proc/" .. pinfo.pid .. "/cmdline"
		local file = io.open(cmdline_path, "r")
		-- And if we find the file we use this as tty
		if file then
			local cmdline = file:read("*a") -- Read the entire file
			file:close()
			-- Replace null characters with spaces
			tty = cmdline:gsub("\0", " ")
		end
	end

	-- Detect git branch and repo root
	local cwd_uri = tostring(pane_info.pane:get_current_working_dir())
	local domain = pane_info.pane:get_domain_name()
	local git_branch = git.get_branch(cwd_uri, domain)
	local git_repo = git.get_repo_root(cwd_uri, domain)

	return {
		pane_id = tostring(pane_info.pane:pane_id()),
		index = pane_info.index,
		is_active = pane_info.is_active,
		is_zoomed = pane_info.is_zoomed,
		left = pane_info.left,
		top = pane_info.top,
		width = pane_info.width,
		height = pane_info.height,
		pixel_width = pane_info.pixel_width,
		pixel_height = pane_info.pixel_height,
		cwd = cwd_uri,
		tty = tty,
		git_branch = git_branch,
		git_repo = git_repo,
	}
end

local shells = {
	["sh"] = true,
	["bash"] = true,
	["zsh"] = true,
	["fish"] = true,
	["nu"] = true,
	["cmd.exe"] = true,
	["powershell.exe"] = true,
	["pwsh.exe"] = true,
	["wsl.exe"] = true,
}

--- Restores a pane from the provided pane data.
--- @param _ any: The window to restore the pane in.
--- @param pane any: The pane to restore.
--- @param pane_data table: The pane data table.
--- @return table|nil: Git branch mismatch info if detected, nil otherwise.
function pub.restore_pane(_, pane, pane_data)
	local mismatch = nil

	-- Restore TTY for Neovim on Linux
	-- NOTE: cwd is handled differently on windows. maybe extend functionality for windows later
	if not fs.is_windows then
		-- get the filename (e.g., "/usr/bin/-zsh" -> "-zsh")
		local program_name = pane_data.tty:match("[^/\\]+$") or pane_data.tty
		-- remove the leading '-' if it's a login shell (e.g., "-zsh" -> "zsh")
		program_name = program_name:gsub("^-", "")
		-- trim leading and trailing whitespace
		program_name = (program_name:match("^%s*(.-)%s*$") or program_name)

		if shells[program_name] then
			-- do nothing, we already have a shell
		elseif pane_data.tty ~= "nil" then
			pane:send_text(pane_data.tty .. "\n")
		end
	end

	-- Check git branch mismatch
	if pane_data.git_branch then
		local path = fs.extract_path_from_dir(pane_data.cwd, pane:get_domain_name())
		local current_branch = git.get_branch_from_path(path)
		wezterm.log_info(
			"Git branch check - path: " .. tostring(path)
			.. ", saved: " .. tostring(pane_data.git_branch)
			.. ", current: " .. tostring(current_branch)
		)
		if current_branch and current_branch ~= pane_data.git_branch then
			mismatch = {
				repo = pane_data.git_repo,
				saved_branch = pane_data.git_branch,
				current_branch = current_branch,
			}
		end
	end

	return mismatch
end

return pub

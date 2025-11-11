local wezterm = require("wezterm")
local tab_mod = require("tab")
local pub = {}

--- Retrieves the current window data from the provided mux window.
-- @param mux_window wezterm.MuxWindow: The mux window to retrieve the window data from.
-- @return table: The window data table.
function pub.retrieve_window_data(mux_window)
	local win_data = {
		title = mux_window:get_title(),
		tabs = {},
	}

	-- Iterate over tabs in the current window
	for _, tab in ipairs(mux_window:tabs_with_info()) do
		local tab_data = tab_mod.retrieve_tab_data(tab.tab)
		tab_data.is_active = tab.is_active
		table.insert(win_data.tabs, tab_data)
	end

	return win_data
end

--- Restore a window from the provided window data.
function pub.restore_window(window, win_data)
	local active_tab
	local initial_pane = window:active_pane()
	local foreground_process = initial_pane:get_foreground_process_name()
	wezterm.log_info("Restoring window panel domain", initial_pane:get_domain_name())
	wezterm.log_info("Restoring window panel hostname", wezterm.hostname())

	local domain = initial_pane:get_domain_name()
	if not domain:find("SSHMUX", 1, true) then
		-- Check if the foreground process is a shell
		if foreground_process then
			if
				foreground_process:find("sh")
				or foreground_process:find("cmd.exe")
				or foreground_process:find("powershell.exe")
				or foreground_process:find("pwsh.exe")
				or foreground_process:find("nu")
				or foreground_process:find("zsh")
			then
				-- Safe to close
				initial_pane:send_text("exit\r")
			else
				wezterm.log_info("Active program detected. Skipping exit command for initial pane.")
			end
		else
			-- Safe to close
			initial_pane:send_text("exit\r")
		end
	end

	for _, tab_data in ipairs(win_data.tabs) do
		local tab = tab_mod.restore_tab(window, tab_data)
		if tab_data.is_active then
			active_tab = tab
		end
	end

	active_tab:activate()
end

return pub

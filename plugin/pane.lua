local wezterm = require("wezterm")
local fs = require('fs')
local pub = {}

--- Retrieve pane data
-- @param pane_info table: The pane information table.
-- @return table: The pane data table.
function pub.retrieve_pane_data(pane_info)
    wezterm.log_info(pane_info, pane_info.pane:get_foreground_process_name(), pane_info.pane:get_foreground_process_info())

    -- default command line from process name
    local tty = tostring(pane_info.pane:get_foreground_process_name())
    -- we try to read process infoo in cmdline proc file to get the full command
    local pinfo = pane_info.pane:get_foreground_process_info()
    if pinfo ~= nil then
        local cmdline_path = "/proc/" .. pinfo.pid .. "/cmdline"
        local file = io.open(cmdline_path, "r")
        -- And if we find the file we use this as tty
        if file then
            local cmdline = file:read("*a")  -- Read the entire file
            file:close()
            -- Replace null characters with spaces
            tty = cmdline:gsub("\0", " ")
        end
    end

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
        cwd = tostring(pane_info.pane:get_current_working_dir()),
        tty = tty
    }
end

--- Resoters a pane from the provided pane data.
--- @TODO: improve tty handling
--- @param _ any: The window to restore the pane in.
--- @param pane any: The pane to restore.
--- @param pane_data table: The pane data table.
function pub.restore_pane(_, pane, pane_data)
    -- Restore TTY for Neovim on Linux
    -- NOTE: cwd is handled differently on windows. maybe extend functionality for windows later
    -- This could probably be handled better in general
    if not (fs.is_windows) then
        if pane_data.tty:match("^sh.*") or
            pane_data.tty:find("cmd.exe") or
            pane_data.tty:find("powershell.exe") or
            pane_data.tty:find("pwsh.exe") or
            pane_data.tty:find("nu") or
            pane_data.tty:find("zsh") then
            -- do nothing, we already have a shell
        elseif pane_data.tty ~= "nil" then
            pane:send_text(pane_data.tty .. "\n")
        end
    end
end

return pub

local wezterm = require("wezterm")
local fs = require("fs")

local git = {}

--- checks if the user is on windows
local is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"

--- Runs a git command in the given directory and returns trimmed stdout, or nil on failure.
--- @param cwd string: The working directory path.
--- @param args string: The git subcommand and arguments.
--- @return string|nil
local function git_cmd(cwd, args)
	local cmd = is_windows
		and string.format('git -C "%s" %s 2>nul', cwd, args)
		or string.format('git -C "%s" %s 2>/dev/null', cwd, args)
	local handle = io.popen(cmd)
	if not handle then
		return nil
	end
	local result = handle:read("*a")
	handle:close()
	if result then
		result = result:gsub("^%s+", ""):gsub("%s+$", "")
		if result ~= "" then
			return result
		end
	end
	return nil
end

--- Returns the current git branch name for the given directory, or nil if not a git repo.
--- @param cwd_uri string: The pane cwd URI (file://...).
--- @param domain string: The pane domain name.
--- @return string|nil
function git.get_branch(cwd_uri, domain)
	local ok, path = pcall(fs.extract_path_from_dir, cwd_uri, domain)
	if not ok or not path or path == "" then
		return nil
	end
	return git_cmd(path, "branch --show-current")
end

--- Returns the git repository root for the given directory, or nil if not a git repo.
--- @param cwd_uri string: The pane cwd URI (file://...).
--- @param domain string: The pane domain name.
--- @return string|nil
function git.get_repo_root(cwd_uri, domain)
	local ok, path = pcall(fs.extract_path_from_dir, cwd_uri, domain)
	if not ok or not path or path == "" then
		return nil
	end
	return git_cmd(path, "rev-parse --show-toplevel")
end

--- Returns the current branch for a local filesystem path (no URI parsing).
--- @param path string: A local directory path.
--- @return string|nil
function git.get_branch_from_path(path)
	if not path or path == "" then
		return nil
	end
	return git_cmd(path, "branch --show-current")
end

return git

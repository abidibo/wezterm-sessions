local wezterm = require 'wezterm'

wezterm.on('gui-startup', function(cmd)
  local dir = wezterm.home_dir .. "/.local/share/wezterm/plugins/httpssCssZssZsgithubsDscomsZsabidibosZswezterm-sessions/state"
  local files = wezterm.read_dir(dir)
  for _, f in ipairs(files) do
    wezterm.log_info("File: " .. f)
  end
  os.exit(0)
end)

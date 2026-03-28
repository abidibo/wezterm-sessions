# WezTerm Sessions

The [WezTerm](https://wezfurlong.org/wezterm/) Sessions is a Lua script enhancement for WezTerm that provides functionality to save, load, restore, edit and delete terminal sessions.

![WezTerm Sessions](./screen.gif)

> [!NOTE]
> While layout saving/loading/restoring should work on Windows, all new functionality are tested only on Linux. Processes restoring, state editing etc... are supported only on Linux and (untested) on macOS.

## Features

- **Save Session State** Captures the current layout of windows, tabs and panes,
  along with their working directories and foreground processes.
- **Restore Session** Reopens a previously saved session that matches the
  current workspace name, restoring its layout and directories.
- **Load Session** Opens a two-step session browser. First, select a
  **workspace** from the list (showing name, date, and window/tab counts).
  Then choose to **load the entire workspace** or pick an **individual tab**
  to restore just that tab (with all its panes) into your current window.
  The fuzzy filter in each step applies only to the items shown.
- **Delete Session State** Allows selecting which saved session to
  delete, regardless of the current workspace name.
- **Edit Session State** Allows selecting which saved session to
  edit, the json file is opened in the `$EDITOR` environment variable, or `nvim` if not set.
- **Fork Session** Creates a new workspace by duplicating the layout of the current one, prompting for a new name. This is useful for experimenting with different layouts without altering the original session.
- **Git Branch Awareness** Saves the current git branch for each pane. When restoring a session, warns if the branch has changed since the last save. Branches are also displayed in the session selection list.
- **Enable/Disable Auto Save** Enables/disables auto saving the current session state.

Edit a state can be useful if you find that the foreground processes of the session are not restored correctly.  
In such cases you can manually set the `tty` string in the state file.

## Installation

**Add to your WezTerm config**

```lua
local wezterm = require("wezterm")
local act = wezterm.action
local sessions = wezterm.plugin.require(
  "https://github.com/abidibo/wezterm-sessions"
)

local config = {}

-- Optional: adds default keybindings and plugin configuration
sessions.apply_to_config(config, {
  -- Auto-save interval in seconds (default: 30)
  auto_save_interval_s = 30,
  -- Warn when git branches changed on restore (default: true)
  git_branch_warn = true,
})

return config
```

> ℹ️ If `apply_to_config` is not called, **no default keybindings** are added and the plugin uses its internal defaults.

---

## 🔧 Plugin Configuration Options

| Option                  | Type    | Default | Description                                           |
| ----------------------- | ------- | ------- | ----------------------------------------------------- |
| `auto_save_interval_s`  | number  | `30`    | Interval (s) between automatic session saves          |
| `git_branch_warn`       | boolean | `true`  | Show a warning when git branches changed on restore   |
| `save_state_dir`        | string  | `nil`   | `nil` = plugin directory, `"default-user-owned"` = `~/.local/share/wezterm-sessions/state/` (`%APPDATA%` on Windows), or a custom absolute path |

---

### ⌨️ Keybindings

#### Default keybindings (optional)

Calling `apply_to_config` adds the following keybindings:

```lua
ALT + s   → Save session
ALT + l   → Load session
ALT + r   → Restore session
CTRL+SHIFT + d → Delete session
CTRL+SHIFT + e → Edit session
ALT + a   → Toggle auto-save
ALT + f   → Fork session
```

---

#### 🔄 Custom keybindings

You may define your own keybindings instead of using the defaults:

```lua
config.keys = {
  {
    key = 's',
    mods = 'ALT',
    action = act({ EmitEvent = "save_session" }),
  },
  {
    key = 'l',
    mods = 'ALT',
    action = act({ EmitEvent = "load_session" }),
  },
  {
    key = 'r',
    mods = 'ALT',
    action = act({ EmitEvent = "restore_session" }),
  },
  {
    key = 'd',
    mods = 'CTRL|SHIFT',
    action = act({ EmitEvent = "delete_session" }),
  },
  {
    key = 'e',
    mods = 'CTRL|SHIFT',
    action = act({ EmitEvent = "edit_session" }),
  },
  {
    key = 'a',
    mods = 'ALT',
    action = act({ EmitEvent = "toggle_autosave" }),
  },
  {
    key = 'f',
    mods = 'ALT',
    action = act({ EmitEvent = "fork_session" }),
  },
}
```

> 💡 If you define your own keybindings, you **do not need** to call `apply_to_config`.

I also recommend to set up a keybinding for creating **named** workspaces or rename the current one:

```lua
  -- Rename current workspace
  {
      key = '$',
      mods = 'CTRL|SHIFT',
      action = act.PromptInputLine {
          description = 'Enter new workspace name',
          action = wezterm.action_callback(
              function(window, pane, line)
                  if line then
                      wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
                  end
              end
          ),
      },
  },
  -- Prompt for a name to use for a new workspace and switch to it.
  {
      key = 'w',
      mods = 'CTRL|SHIFT',
      action = act.PromptInputLine {
          description = wezterm.format {
              { Attribute = { Intensity = 'Bold' } },
              { Foreground = { AnsiColor = 'Fuchsia' } },
              { Text = 'Enter name for new workspace' },
          },
          action = wezterm.action_callback(function(window, pane, line)
              -- line will be `nil` if they hit escape without entering anything
              -- An empty string if they just hit enter
              -- Or the actual line of text they wrote
              if line then
                  window:perform_action(
                      act.SwitchToWorkspace {
                          name = line,
                      },
                      pane
                  )
              end
          end),
      },
  },
```

## Events

The following events are emitted:

- `wezterm-sessions.save.start(file_path)`
- `wezterm-sessions.save.end(file_path, res)`
- `wezterm-sessions.load.start(workspace_name)`
- `wezterm-sessions.load.end(workspace_name)`
- `wezterm-sessions.restore.start(workspace_name)`
- `wezterm-sessions.restore.end(workspace_name)`
- `wezterm-sessions.delete.start(file_path)`
- `wezterm-sessions.delete.end(file_path, res)`
- `wezterm-sessions.edit.start(file_path, editor)`
- `wezterm-sessions.git.branch_mismatch(workspace_name, mismatches)` — fired when branches differ on restore. `mismatches` is a list of `{ repo, saved_branch, current_branch }` tables.

## Limitations

There are currently some limitations and improvements that need to be implemented:

- The script is a fork of the original [WezTerm Session Manager](https://github.com/danielcopper/wezterm-session-manager) created by [Daniel Copper](https://github.com/danielcopper),
which had some limitations I tried to fix, but also it was tested both on linux and windows. On the contrary I'm only interested on linux and so new functionality won't be tested on windows (if windows users are willing to help, they're welcome).
- The script tries to restore the running processes (only on mac/linux) in each pane, and it does this by inspecting the `proc` `cmdline` file. Probably this can be improved and probably
not all processes can be restored succesfully.
- The script does not treat remote sessions in a special way at the moment, and for what I read, there are some differences in WezTerm available infos for remote sessions. So maybe this doesn't work well in this scenario. It works well on local and unix domains.
- The script should be able to restore even complex workspaces layouts, but who knows :)

## Credits

This project is now developed by [abidibo](https://github.com/abidibo).

It is a fork of the original [WezTerm Session Manager](https://github.com/danielcopper/wezterm-session-manager) created by [Daniel Copper](https://github.com/danielcopper).

You can also be interested in other WezTerm related projects:

- [wezterm-cmdpicker](https://github.com/abidibo/wezterm-cmdpicker) - A WezTerm plugin that adds a command-palette-style fuzzy picker for keybindings. Press a trigger key to search and execute any keybinding — user-defined, config, or WezTerm defaults.

## Contributing

Feedback, bug reports, and contributions to enhance the script are welcome.

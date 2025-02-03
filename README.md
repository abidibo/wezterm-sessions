# WezTerm Sessions

The [WezTerm](https://wezfurlong.org/wezterm/) Sessions is a Lua script
enhancement for WezTerm that provides functionality to save, load, and restore
terminal sessions. This tool helps manage terminal sessions, its goal is to save
and restore different sessions or better workspaces and later restore them.

![WezTerm Sessions](./screen.gif)

## Features

- **Save Session State** Captures the current layout of windows, tabs and panes,
  along with their working directories and foreground processes.
- **Restore Session** Reopens a previously saved session that matches the
  current workspace name, restoring its layout and directories.
- **Load Session** Allows selecting which saved session to
  load, regardless of the current workspace name.
- **Delete Session State** Allows selecting which saved session to
  delete, regardless of the current workspace name.
- **Edit Session State** Allows selecting which saved session to
  edit, the json file is opened in the `$EDITOR` environment variable, or `nvim` if not set.

Edit a state can be useful if you find that the foreground processes of the session are not restored correctly.  
In such cases you can manually set the `tty` string in the state file.

## Installation

**Add to your wezterm config**

   ```lua
    local sessions = wezterm.plugin.require("https://github.com/abidibo/wezterm-sessions")
    sessions.apply_to_config(config) -- optional, this adds default keybindings
   ```

## Configuration

1. **Event Bindings:** You can define your own keybindings:

    ```lua
    -- there are the default ones
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
    }
   ```

2. I also recommend to set up a keybinding for creating **named** workspaces or rename the current one:

    ````lua 
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
    ```
   
## Events

The following events are emitted:

- `wezter-sessions.save.start(file_path)`
- `wezter-sessions.save.end(file_path, res)`
- `wezter-sessions.load.start(workspace_name)`
- `wezter-sessions.load.end(workspace_name)`
- `wezter-sessions.restore.start(workspace_name)`
- `wezter-sessions.restore.end(workspace_name)`
- `wezter-sessions.delete.start(file_path)`
- `wezter-sessions.delete.end(file_path, res)`
- `wezter-sessions.edit.start(file_path, editor)`

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

## Contributing

Feedback, bug reports, and contributions to enhance the script are welcome.

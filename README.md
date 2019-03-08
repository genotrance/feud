Feud is a text editor based on Scintilla and written in Nim

The primary focus is perforamnce and minimal memory and CPU usage. All functionality is implemented with
the plugin system which exposes the internals for easy extensibility. The feature list is effectively the
list of plugins and their capabilities.

Feud is built with Nim which is key in achieving its performance goals - both in terms of user and developer
experience.

Feud only supports Windows but aims to be cross-platform once basic functionality is implemented. Syntax
highlighting and themes are supported.

## Navigation

Use the `^E` hotkey to bring up the command popup to run any of the following commands. This runs the
`togglePopup` command internally.

Opening files:
```
open path\to\file.txt  - open specific file
open ..\*.nim          - open all files that match wildcard
open path\to\dir       - open all files in directory

reload                 - reload current buffer
save                   - save current buffer
```

Switching buffers:
```
open path\to\file      - switch to buffer if already open
open 4                 - switch by buffer number
open patfi             - fuzzy search to find buffer
prev                   - switch to previous buffer
next                   - switch to next buffer
```

Closing files:
```
close                  - close current buffer
close X                - close buffer similar to switching
closeAll               - close all open buffers
```

Windows:
```
newWindow              - open a new editor window
closeWindow            - close current window
```

Hotkeys:
```
! = Alt
^ = Ctrl
+ = Shift
# = Win
* = Global

hotkey ^n newWindow    - create a new app-local hotkey
hotkey ^n              - remove registered hotkey
```

Hotkeys can map to a complete command with params to speed up common tasks.

A few default hotkeys are defined in `feud.ini`.

Aliases:
```
alias o open           - create a short alias for the open command
alias n open *.nim     - alias with params
```

__Configuration file__

`feud.ini` is effectively a list of editor and plugin commands to run on load. This includes setting up hooks
that allow customization of plugin and editor behavior.

Reload configuration with command `config`.

__Scintilla__

The `eMsg` command can be used to send any message to the current editor window. This allows plugins and the
user to perform many common and advanced tasks directly without having to author a plugin.

```
eMsg SCI_SETUSETABS 0  - set Scintilla to replace tabs with spaces
eMsg SCI_SETTABWIDTH 2 - set Scintilla to set tab width to 2
```

The full documentation for Scintilla is available [here](https://www.scintilla.org/ScintillaDoc.html).

__Hooks__

Plugin authors can use hooks to allow users to run custom commands at specific points in their code. For example,
the `file` plugin enables two hooks: `onFileLoad` and `onFileSwitch`. This allows a user to run custom commands
at that point. For example:

```
hook onFileSwitch eMsg SCI_SETUSETABS 0
hook onFileSwitch eMsg SCI_SETTABWIDTH 2
```

This now runs these two `eMsg` commands whenever you switch buffers. The plugin would need to run the `runHook name`
command internally.

Hooks can be deleted with `delHook name`.

__Remote Navigation__

Feud has an RPC plugin that allows remote navigation. The `feudc` command-line tool can be used to remote
control a local or remote GUI instance. The interface is still being designed so is a POC at this point.

Commands: `initServer restartServer stopServer sendServer`

## Feedback

Feud is a work in progress and any feedback or suggestions are welcome. It is hosted on [GitHub](https://github.com/genotrance/feud) with an MIT license so issues, forks and PRs are most appreciated.

__Credits__

https://nim-lang.org
https://www.scintilla.org
https://github.com/nanomsg/nng
https://github.com/forrestthewoods/lib_fts
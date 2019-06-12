import os, osproc, strformat, strutils

import "../../src"/pluginapi

proc exec(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    command =
      when defined(Windows):
        "cmd /c "
      else:
        ""

  if cmd.params.len != 0:
    let
      (output, exitCode) = execCmdEx(command & cmd.params.join(" "))

    plg.ctx.notify(plg.ctx, &"{output}Returned: {$exitCode}")

feudPluginLoad()
import os, osproc, strformat

import "../../src"/pluginapi

proc exec(plg: var Plugin) {.feudCallback.} =
  var
    cmd =
      when defined(Windows):
        "cmd /c"
      else:
        ""

  for param in plg.getParam():
    let
      (output, exitCode) = execCmdEx(param)

    plg.ctx.notify(plg.ctx, &"{output}Returned: {$exitCode}")

feudPluginLoad()
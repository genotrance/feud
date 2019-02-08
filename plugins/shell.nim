import os, osproc, segfaults, strformat

import "../src"/pluginapi

proc exec(plg: var Plugin) {.feudCallback.} =
  var
    cmd =
      when defined(Windows):
        "cmd /c"
      else:
        ""

  cmd &= plg.ctx.cmdParam

  let
    (output, exitCode) = execCmdEx(cmd)

  plg.ctx.notify(plg.ctx, &"{output}Returned: {$exitCode}")

feudPluginLoad()
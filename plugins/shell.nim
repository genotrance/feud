import os, osproc, strformat

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

  plg.ctx.notify(&"{output}Returned: {$exitCode}")

feudPluginLoad()
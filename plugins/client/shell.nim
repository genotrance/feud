import os, osproc, segfaults, strformat

import "../../src"/pluginapi

proc exec(plg: var Plugin) {.feudCallback.} =
  var
    cmd =
      when defined(Windows):
        "cmd /c"
      else:
        ""

  if plg.ctx.cmdParam.len != 0:
    cmd &= plg.ctx.cmdParam[0]

  let
    (output, exitCode) = execCmdEx(cmd)

  plg.ctx.notify(plg.ctx, &"{output}Returned: {$exitCode}")

feudPluginLoad()
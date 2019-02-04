import os, osproc, strformat

import "../src"/pluginapi

proc exec(ctx: var Ctx, plg: var Plugin) {.feudCallback.} =
  var
    cmd =
      when defined(Windows):
        "cmd /c"
      else:
        "bash -c \""

  cmd &= ctx.cmdParam

  let
    (output, exitCode) = execCmdEx(cmd)

  ctx.notify(&"{output}Returned: {$exitCode}")

feudPluginLoad()
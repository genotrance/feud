import os, osproc, streams, strformat, strutils, times

import "../../src"/pluginapi

proc execLive(plg: var Plugin, cmd: string) =
  let
    cmd =
      when defined(Windows):
        ("cmd /c " & cmd).parseCmdLine()
      else:
        cmd.parseCmdLine()
    command = cmd[0]
    args =
      if cmd.len > 1:
        cmd[1 .. ^1]
      else:
        @[]

  var
    line: string
    p = startProcess(command, args=args, options={poUsePath})
    sout = p.outputStream()

  try:
    while true:
      if p.running():
        line = sout.readLine() & "\n"
      else:
        break

      discard plg.ctx.msg(plg.ctx, SCI_ADDTEXT, line.len, line.cstring)
  except IOError, OSError:
    discard

  sout.close()

  let
    err = p.waitForExit()

  if err != 0:
    plg.ctx.notify(plg.ctx, "Command failed: " & $err)

proc exec(plg: var Plugin) {.feudCallback.} =
  var
    params = plg.getParam()

  for param in params:
    plg.execLive(param)

proc execNew(plg: var Plugin) {.feudCallback.} =
  let
    params = plg.getParam()

  if plg.ctx.handleCommand(plg.ctx, "newDoc"):
    for param in params:
      plg.execLive(param)

proc saveToTemp(plg: var Plugin): tuple[tmpfile: string, selection: bool] =
  result.tmpfile = getTempDir() / "feud_shell_" & $(getTime().toUnix()) & ".txt"

  discard plg.ctx.msg(plg.ctx, SCI_SETREADONLY, 1.toPtr)

  var
    data = plg.getSelection().cstring

  if data.len != 0:
    result.selection = true
  else:
    data = cast[cstring](plg.ctx.msg(plg.ctx, SCI_GETCHARACTERPOINTER))

  try:
    var
      f = open(result.tmpfile, fmWrite)
    f.write(data)
    f.close()
  except:
    plg.ctx.notify(plg.ctx, &"Failed to save {result.tmpfile}")
    result.tmpfile = ""
  finally:
    discard plg.ctx.msg(plg.ctx, SCI_SETREADONLY, 0.toPtr)

proc execPipe(plg: var Plugin, tmpfile: string, params: seq[string]) =
  for param in params:
    let
      cmd =
        when defined(Windows):
          &"type {tmpfile.quoteShell} | cmd /c {param}"
        else:
          &"cat {tmpfile.quoteShell} | {param}"

    plg.execLive(cmd)

  if tmpfile.tryRemoveFile() == false:
    plg.ctx.notify(plg.ctx, &"Failed to remove {tmpfile}")

proc pipe(plg: var Plugin) {.feudCallback.} =
  var
    params = plg.getParam()
    (tmpfile, selection) = plg.saveToTemp()

  if tmpfile.len != 0:
    if not selection:
      discard plg.ctx.msg(plg.ctx, SCI_CLEARALL)
    else:
      discard plg.ctx.msg(plg.ctx, SCI_CLEAR)

    plg.execPipe(tmpfile, params)

proc pipeNew(plg: var Plugin) {.feudCallback.} =
  var
    params = plg.getParam()
    (tmpfile, selection) = plg.saveToTemp()

  if tmpfile.len != 0:
    if plg.ctx.handleCommand(plg.ctx, "newDoc"):
      plg.execPipe(tmpfile, params)

feudPluginDepends(["alias", "window"])

feudPluginLoad:
  discard plg.ctx.handleCommand(plg.ctx, "alias ! execNew")
  discard plg.ctx.handleCommand(plg.ctx, "alias !> exec")

  discard plg.ctx.handleCommand(plg.ctx, "alias | pipeNew")
  discard plg.ctx.handleCommand(plg.ctx, "alias |> pipe")
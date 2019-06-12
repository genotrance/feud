import os, osproc, streams, strformat, strutils, times

import "../../src"/pluginapi

proc execLive(plg: var Plugin, cmd: var CmdData) =
  when defined(Windows):
    cmd.params = @["cmd", "/c"] & cmd.params

  let
    command = cmd.params[0]
    args =
      if cmd.params.len > 1:
        cmd.params[1 .. ^1]
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
    cmd.failed = true

  sout.close()

  let
    err = p.waitForExit()

  if err != 0:
    plg.ctx.notify(plg.ctx, "Command failed: " & $err)
    cmd.failed = true

  plg.gotoEnd()

proc exec(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  plg.execLive(cmd)

  var
    ccmd = newCmdData("togglePopup !>")
  plg.ctx.handleCommand(plg.ctx, ccmd)

proc execNew(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    ccmd = newCmdData("newDoc")
  plg.ctx.handleCommand(plg.ctx, ccmd)
  if not ccmd.failed:
    plg.execLive(cmd)
  else:
    cmd.failed = true

  ccmd = newCmdData("togglePopup !>")
  plg.ctx.handleCommand(plg.ctx, ccmd)

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

proc execPipe(plg: var Plugin, cmd: var CmdData, tmpfile: string) =
  var
    command =
      when defined(Windows):
        &"""type {tmpfile.quoteShell} | cmd /c {cmd.params.join(" ")}"""
      else:
        &"""cat {tmpfile.quoteShell} | {cmd.params.join(" ")}"""
    ccmd = newCmdData(command)

  plg.execLive(ccmd)
  if ccmd.failed:
    cmd.failed = true

  if tmpfile.tryRemoveFile() == false:
    plg.ctx.notify(plg.ctx, &"Failed to remove {tmpfile}")

proc pipe(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    (tmpfile, selection) = plg.saveToTemp()

  if tmpfile.len != 0:
    if not selection:
      discard plg.ctx.msg(plg.ctx, SCI_CLEARALL)
    else:
      discard plg.ctx.msg(plg.ctx, SCI_CLEAR)

    plg.execPipe(cmd, tmpfile)

proc pipeNew(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    (tmpfile, selection) = plg.saveToTemp()
    ccmd = newCmdData("newDoc")

  if tmpfile.len != 0:
    plg.ctx.handleCommand(plg.ctx, ccmd)
    if not ccmd.failed:
      plg.execPipe(cmd, tmpfile)
    else:
      cmd.failed = true

  ccmd = newCmdData("togglePopup !>")
  plg.ctx.handleCommand(plg.ctx, ccmd)

feudPluginDepends(["alias", "window"])

feudPluginLoad:
  for i in [
    "alias ! execNew",
    "alias !> exec",
    "alias | pipeNew",
    "alias |> pipe"
  ]:
    var
      ccmd = newCmdData(i)
    plg.ctx.handleCommand(plg.ctx, ccmd)

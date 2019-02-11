import sets, strutils, tables

when defined(Windows):
  import "."/win

import "."/[globals, plugin]

import ".."/wrappers/scintilla

proc toInt(sval: string, ival: var int): bool =
  let
    parseProc = if "0x" in sval: parseHexInt else: parseInt

  try:
    ival = sval.parseProc()
    result = true
  except:
    discard

proc execMsg(ctx: var Ctx, cmd, param: string) =
  let
    spl = param.split(" ", maxsplit=3)
    msgProc = if cmd == "emsg": eMsg else: cMsg

  var
    s, l, w: int
    wc: cstring

  if not spl[0].toInt(s):
    ctx.notify(ctx, "Bad integer value " & spl[0])
    return

  if spl.len > 1:
    if not spl[1].toInt(l):
      ctx.notify(ctx, "Bad integer value " & spl[1])
      return

    if spl.len > 2:
      if not spl[2].toInt(w):
        wc = spl[2].cstring
        ctx.notify(ctx, $msgProc(s, l, wc))
      else:
        ctx.notify(ctx, $msgProc(s, l, w))
    else:
      ctx.notify(ctx, $msgProc(s, l))
  else:
    ctx.notify(ctx, $msgProc(s))

proc handleCommand*(ctx: var Ctx, command: string) =
  let
    spl = command.strip().split(" ", maxsplit=1)
    cmd = spl[0]

  var param = if spl.len == 2: spl[1] else: ""

  case cmd:
    of "emsg", "cmsg":
      if param.len != 0:
        ctx.execMsg(cmd, param)
    of "quit", "exit":
      exitWindow()
    else:
      if param.len != 0:
        ctx.cmdParam = @[param]
      else:
        ctx.cmdParam = @[]
      discard ctx.handlePluginCommand(cmd)

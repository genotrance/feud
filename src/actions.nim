import sets, strutils, tables

when defined(Windows):
  import "."/win

import "."/[globals, plugin, scintilla]

proc toInt(sval: string, ival: var int): bool =
  let
    parseProc = if "0x" in sval: parseHexInt else: parseInt

  try:
    ival = sval.parseProc()
    result = true
  except:
    discard

proc execMsg(cmd, param: string, ctx: var Ctx) =
  let
    spl = param.split(" ", maxsplit=3)
    msgProc = if cmd == "emsg": eMsg else: cMsg

  var
    s, l, w: int
    wc: cstring

  if not spl[0].toInt(s):
    ctx.notify("Bad integer value " & spl[0])
    return

  if spl.len > 1:
    if not spl[1].toInt(l):
      ctx.notify("Bad integer value " & spl[1])
      return

    if spl.len > 2:
      if not spl[2].toInt(w):
        wc = spl[2].cstring
        ctx.notify($msgProc(s, l, wc))
      else:
        ctx.notify($msgProc(s, l, w))
    else:
      ctx.notify($msgProc(s, l))
  else:
    ctx.notify($msgProc(s))

proc handleCommand*(command: string, ctx: var Ctx) =
  let
    spl = command.strip().split(" ", maxsplit=1)
    cmd = spl[0]

  var param = if spl.len == 2: spl[1] else: ""

  case cmd:
    of "emsg", "cmsg":
      if param.len != 0:
        execMsg(cmd, param, ctx)
    of "quit", "exit":
      exitWindow()
    else:
      ctx.cmdParam = param
      handlePluginCommand(cmd, ctx)

  ctx.notify("")
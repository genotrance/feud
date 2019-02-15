import os, strutils, tables

when defined(Windows):
  import winim/inc/[windef, winbase, winuser], winim/winstr

import "../../src"/pluginapi

type
  Window = ref object
    current*: int
    editors*: seq[pointer]

proc getWindow(plg: var Plugin): Window =
  return getPlgData[Window](plg)

proc createWindow(name = "", show = true): HWND =
  result = CreateWindow("Scintilla", name, WS_OVERLAPPEDWINDOW, 10, 10, 800, 600, 0, 0, GetModuleHandleW(nil), nil)
  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  if show:
    result.ShowWindow(SW_SHOW)

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

proc getPlugin(ctx: var Ctx): Plugin =
  for pl in ctx.plugins.keys():
    if pl == currentSourcePath.splitFile().name:
      return ctx.plugins[pl]

proc getCurrentWindow(ctx: var Ctx): int =
  var
    plg = ctx.getPlugin()
    window = plg.getWindow()

  return window.current

proc msg*(ctx: var Ctx, msgID: int, wparam: pointer = nil, lparam: pointer = nil, windowID = -1): int {.discardable.} =
  var
    plg = ctx.getPlugin()
    window = plg.getWindow()

  let
    winid =
      if windowID == -1:
        ctx.getCurrentWindow()
      else:
        windowID

  if windowID > window.editors.len-1:
    return -1
  return SendMessage(cast[HWND](window.editors[winid]), cast[UINT](msgID), cast[WPARAM](wparam), cast[LPARAM](lparam))

proc toInt(sval: string, ival: var int): bool =
  let
    parseProc = if "0x" in sval: parseHexInt else: parseInt

  try:
    ival = sval.parseProc()
    result = true
  except:
    discard

proc eMsg(plg: var Plugin) {.feudCallback.} =
  for param in plg.ctx.cmdParam:
    let
      spl = param.split(" ", maxsplit=3)

    var
      s, l, w: int
      wc: cstring

    if SciDefs.hasKey(spl[0]):
      s = SciDefs[spl[0]]
    elif not spl[0].toInt(s):
      plg.ctx.notify(plg.ctx, "Bad SCI value " & spl[0])
      continue

    if spl.len > 1:
      if SciDefs.hasKey(spl[1]):
        l = SciDefs[spl[1]]
      elif not spl[1].toInt(l):
        plg.ctx.notify(plg.ctx, "Bad integer value " & spl[1])
        continue

      if spl.len > 2:
        if not spl[2].toInt(w):
          wc = spl[2].cstring
          plg.ctx.notify(plg.ctx, $msg(plg.ctx, s, l, wc))
        else:
          plg.ctx.notify(plg.ctx, $msg(plg.ctx, s, l, w))
      else:
        plg.ctx.notify(plg.ctx, $msg(plg.ctx, s, l))
    else:
      plg.ctx.notify(plg.ctx, $msg(plg.ctx, s))

proc setCurrentWindow(window: var Window, closeid: int) =
  if closeid > 0:
    if closeid == window.current:
      if closeid == window.editors.len-1:
        window.current = window.current - 1
      else:
        window.current = window.current + 1
    else:
      if closeid < window.current:
        window.current -= 1

feudPluginLoad:
  var
    window = plg.getWindow()

  window.editors.add cast[pointer](createWindow(show=false))
  window.editors.add cast[pointer](createWindow())
  window.current = 1

  plg.ctx.msg = msg

feudPluginTick:
  var
    msg: MSG
    lpmsg = cast[LPMSG](addr msg)
    window = plg.getWindow()

  if PeekMessageW(lpmsg, 0, 0, 0, PM_REMOVE) > 0:
    discard TranslateMessage(addr msg)
    discard DispatchMessageW(addr msg)

  for i in countdown(window.editors.len-1, 0):
    if IsWindow(cast[HWND](window.editors[i])) == 0:
      DestroyWindow(cast[HWND](window.editors[i]))
      window.setCurrentWindow(i)
      discard window.editors.pop()
  if window.editors.len == 1:
    plg.ctx.handleCommand(plg.ctx, "quit")

feudPluginUnload:
  var
    window = plg.getWindow()

  for i in countdown(window.editors.len-1, 0):
    DestroyWindow(cast[HWND](window.editors[i]))
    window.setCurrentWindow(i)
    discard window.editors.pop()

  freePlgData[Window](plg)

  plg.ctx.msg = nil

# proc setEditorTitle*(title: string) =
  # gWin.editor.SetWindowText(title.newWideCString)

# proc setCommandTitle*(title: string) =
  # gWin.command.SetWindowText(title.newWideCString)

# proc commandCallback(ctx: var Ctx) =
  # let
    # pos = SCI_GETCURRENTPOS.cMsg()
    # line = SCI_LINEFROMPOSITION.cMsg(pos)
    # length = SCI_LINELENGTH.cMsg(line)

  # if length != 0:
    # var
      # data = alloc0(length+1)
    # defer: data.dealloc()

    # if SCI_GETLINE.cMsg(line, data) == length:
      # handleCommand(ctx, $cast[cstring](data))

# proc notify(msg: string) =
  # let
    # msgn = "\n" & msg
  # SCI_APPENDTEXT.cMsg(msgn.len, msgn.cstring)
  # SCI_GOTOPOS.cMsg(SCI_GETLENGTH.cMsg())

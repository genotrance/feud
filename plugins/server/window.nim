import hashes, os, strformat, strutils, tables

when defined(Windows):
  import winim/inc/[windef, winbase, winuser], winim/winstr

import "../../src"/pluginapi

type
  Window = ref object
    current*: int
    editors*: seq[pointer]
    hotkeys*: TableRef[int, tuple[hotkey, callback: string]]

proc getWindow(plg: var Plugin): Window =
  return getPlgData[Window](plg)

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

proc createPopup(): HWND =
  result = CreateWindow("Scintilla", "", WS_BORDER, 10, 10, 800, 50, 0, 0, GetModuleHandleW(nil), nil)
  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  var
    style = result.GetWindowLong(GWL_STYLE)
  style = style and not WS_CAPTION
  result.SetWindowLong(GWL_STYLE, style)

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

proc createWindow(name = "", show = true): HWND =
  result = CreateWindow("Scintilla", name, WS_OVERLAPPEDWINDOW, 10, 10, 800, 800, 0, 0, GetModuleHandleW(nil), nil)
  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  if show:
    result.ShowWindow(SW_SHOW)

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

proc toInt(sval: string, ival: var int): bool =
  let
    parseProc = if "0x" in sval: parseHexInt else: parseInt

  try:
    ival = sval.parseProc()
    result = true
  except:
    discard

proc eMsg(plg: var Plugin) {.feudCallback.} =
  var
    params = plg.ctx.cmdParam.deepCopy()
  for param in params:
    let
      spl = param.split(" ", maxsplit=3)

    var
      s, l, w: int
      wc: cstring
      ret: int

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
          ret = msg(plg.ctx, s, l, wc)
        else:
          ret = msg(plg.ctx, s, l, w)
      else:
        ret = msg(plg.ctx, s, l)
    else:
      ret = msg(plg.ctx, s)

    plg.ctx.notify(plg.ctx, "Returned: " & $ret)

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

proc newWindow(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()

  window.editors.add cast[pointer](createWindow())
  window.current = window.editors.len-1

  plg.ctx.handleCommand(plg.ctx, "setTheme")

proc closeWindow(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()
    winid = window.current

  if plg.ctx.cmdParam.len != 0:
    try:
      winid = plg.ctx.cmdParam[0].parseInt()
    except:
      return

  if winid < window.editors.len:
    DestroyWindow(cast[HWND](window.editors[winid]))
    window.setCurrentWindow(winid)
    window.editors.delete(winid)

proc togglePopup(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()
    hwnd = cast[HWND](window.editors[0])

  if hwnd.IsWindowVisible() == 1:
    hwnd.ShowWindow(SW_HIDE)
  else:
    hwnd.ShowWindow(SW_SHOW)

proc hotkey(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()
  if plg.ctx.cmdParam.len == 0:
    var hout = ""

    for hotkey in window.hotkeys.keys():
      hout &= window.hotkeys[hotkey].hotkey & " = " & window.hotkeys[hotkey].callback & "\n"

    if hout.len != 0:
      plg.ctx.notify(plg.ctx, hout[0 .. ^2])
  else:
    let
      params = plg.ctx.cmdParam.deepCopy()
    for param in params:
      let
        spl = param.strip().split(" ", maxsplit=1)
        hotkey = spl[0].strip()
        id = hotkey.hash().abs()
      if spl.len == 2:
        var
          fsModifiers = MOD_NOREPEAT
          vk: char

        for i in hotkey:
          case i:
            of '#':
              fsModifiers = fsModifiers or MOD_WIN
            of '^':
              fsModifiers = fsModifiers or MOD_CONTROL
            of '!':
              fsModifiers = fsModifiers or MOD_ALT
            of '+':
              fsModifiers = fsModifiers or MOD_SHIFT
            else:
              vk = i.toUpperAscii

        if RegisterHotKey(0, id.int32, fsModifiers.UINT, vk.UINT) != 1:
          plg.ctx.notify(plg.ctx, strformat.`&`("Failed to register hotkey {hotkey}"))
        else:
          window.hotkeys[id] = (hotkey, spl[1].strip())
      else:
        if UnregisterHotKey(0, id.int32) != 1:
          plg.ctx.notify(plg.ctx, strformat.`&`("Failed to unregister hotkey {hotkey}"))
        else:
          window.hotkeys.del(id)

feudPluginLoad:
  var
    window = plg.getWindow()

  window.editors.add cast[pointer](createPopup())
  window.editors.add cast[pointer](createWindow(show=false))
  window.editors.add cast[pointer](createWindow())
  window.current = 2

  window.hotkeys = newTable[int, tuple[hotkey, callback: string]]()

  plg.ctx.msg = msg

  plg.ctx.handleCommand(plg.ctx, "setTheme")
  plg.ctx.handleCommand(plg.ctx, "setPopupTheme")

feudPluginTick:
  var
    msg: MSG
    lpmsg = cast[LPMSG](addr msg)
    window = plg.getWindow()

  if PeekMessageW(lpmsg, 0, 0, 0, PM_REMOVE) > 0:
    if msg.message == WM_HOTKEY:
      let
        id = msg.wparam.int
      if window.hotkeys.hasKey(id):
        plg.ctx.handleCommand(plg.ctx, window.hotkeys[id].callback)
    elif msg.hwnd == cast[HWND](window.editors[0]) and msg.message == WM_KEYDOWN and msg.wparam == VK_ESCAPE:
      plg.togglePopup()
    else:
      discard TranslateMessage(addr msg)
      discard DispatchMessageW(addr msg)

  if plg.ctx.tick mod 20 == 0:
    for i in countdown(window.editors.len-1, 0):
      if IsWindow(cast[HWND](window.editors[i])) == 0:
        DestroyWindow(cast[HWND](window.editors[i]))
        window.setCurrentWindow(i)
        window.editors.delete(i)
    if window.editors.len == 2:
      plg.ctx.handleCommand(plg.ctx, "quit")

feudPluginUnload:
  var
    window = plg.getWindow()

  for i in countdown(window.editors.len-1, 0):
    DestroyWindow(cast[HWND](window.editors[i]))
    window.setCurrentWindow(i)
    discard window.editors.pop()

  for hotkey in window.hotkeys.keys():
    let
      id = hotkey.hash().abs()
    UnregisterHotKey(0, id.int32)

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

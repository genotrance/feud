import os, strformat, strutils, tables, times

when defined(Windows):
  import winim/inc/[windef, winbase, winuser], winim/winstr

import "../.."/src/pluginapi

type
  Window = ref object
    last: Time
    current: int
    frames: seq[pointer]
    editors: seq[pointer]
    hotkeys: TableRef[int, tuple[hotkey, callback: string]]

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

proc resizeFrame(hwnd: HWND) =
  let
    editor = hwnd.GetWindow(GW_CHILD)

  if editor != 0:
    var
      rect: Rect
    if hwnd.GetClientRect(addr rect) == 1:
      discard SetWindowPos(
        editor,
        HWND_TOP,
        rect.left,
        rect.top,
        rect.right-rect.left,
        rect.bottom-rect.top,
        SWP_SHOWWINDOW)

proc frameCallback(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  case msg:
    of WM_SIZE:
      hwnd.resizeFrame()
    of WM_CLOSE:
      hwnd.DestroyWindow()
    of WM_DESTROY:
      PostQuitMessage(0)
    else:
      return DefWindowProc(hwnd, msg, wParam, lParam)

  return 0

proc registerFrame() =
  var
    wc: WNDCLASSEX

  wc.cbSize        = sizeof(WNDCLASSEX).int32
  wc.style         = 0
  wc.lpfnWndProc   = frameCallback
  wc.cbClsExtra    = 0
  wc.cbWndExtra    = 0
  wc.hInstance     = GetModuleHandleW(nil)
  # wc.hIcon         = LoadIcon(NULL, IDI_APPLICATION);
  # wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
  # wc.hbrBackground = (HBRUSH)(COLOR_WINDOW+1);
  # wc.lpszMenuName  = NULL;
  wc.lpszClassName = "FeudFrame"
  # wc.hIconSm       = LoadIcon(NULL, IDI_APPLICATION);

  doException RegisterClassEx(addr wc) != 0, "Frame registration failed with " & $GetLastError()

proc unregisterFrame() =
  doException UnregisterClass("FeudFrame", GetModuleHandleW(nil)) != 0, "Frame unregistration failed with " & $GetLastError()

proc createFrame(show = true): HWND =
  result = CreateWindowEx(
    WS_EX_OVERLAPPEDWINDOW, "FeudFrame", "", WS_OVERLAPPEDWINDOW,
    10, 10, 1200, 800, 0, 0, GetModuleHandleW(nil), nil)

  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  if show:
    result.ShowWindow(SW_SHOW)

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

proc createPopup(): HWND =
  result = CreateWindow("Scintilla", "", WS_BORDER, 10, 10, 800, 30, 0, 0, GetModuleHandleW(nil), nil)
  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  var
    style = result.GetWindowLong(GWL_STYLE)
  style = style and not WS_CAPTION
  result.SetWindowLong(GWL_STYLE, style)

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

proc createWindow(parent: HWND = 0, name = "", show = true): HWND =
  result = CreateWindow("Scintilla", name, WS_CHILD, 0, 0, 1200, 800, parent, 0, GetModuleHandleW(nil), nil)
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

proc getWinidFromHwnd(window: var Window, hwnd: HWND): int =
  result = window.frames.find(hwnd)
  if result == -1:
    result = window.editors.find(hwnd)

proc newWindow(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()
    frame = createFrame()

  window.frames.add cast[pointer](frame)
  window.editors.add cast[pointer](createWindow(frame))
  frame.resizeFrame()
  window.current = window.editors.len-1
  msg(plg.ctx, SCI_GRABFOCUS)

  discard plg.ctx.handleCommand(plg.ctx, "setTheme")

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
    DestroyWindow(cast[HWND](window.frames[winid]))
    window.setCurrentWindow(winid)
    window.editors.delete(winid)
    window.frames.delete(winid)
    msg(plg.ctx, SCI_GRABFOCUS)

proc positionPopup(hwnd: HWND) =
  var
    fghwnd = GetForegroundWindow()
    rect: RECT

  if fghwnd.GetWindowRect(addr rect) == 1:
    discard hwnd.SetWindowPos(
      fghwnd,
      rect.left+25,
      rect.bottom-rect.top-40,
      rect.right-rect.left-50,
      30,
      SWP_SHOWWINDOW)

proc togglePopup(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()
    hwnd = cast[HWND](window.editors[0])

  if hwnd.IsWindowVisible() == 1:
    msg(plg.ctx, SCI_CLEARALL, windowid=0)
    hwnd.ShowWindow(SW_HIDE)
    msg(plg.ctx, SCI_GRABFOCUS)
  else:
    hwnd.positionPopup()
    if plg.ctx.cmdParam.len != 0:
      let
        param = plg.ctx.cmdParam[0].deepCopy()
      msg(plg.ctx, SCI_APPENDTEXT, param.len+1, (param & " ").cstring, windowid=0)
      msg(plg.ctx, SCI_GOTOPOS, param.len+1, windowid=0)
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
        (hotkey, val) = param.splitCmd()

      var
        global = false
        fsModifiers: UINT
        vk: char
        id = 0
        ret = 0

      for i in hotkey:
        case i:
          of '*':
            global = true
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

      id = fsModifiers or (vk.int shl 8)

      if val.len != 0:
        ret =
          if global:
            RegisterHotKey(0, id.int32, fsModifiers or MOD_NOREPEAT, vk.UINT)
          else:
            1

        if ret != 1:
          plg.ctx.notify(plg.ctx, strformat.`&`("Failed to register hotkey {hotkey}"))
        else:
          window.hotkeys[id] = (hotkey, val)
      else:
        ret =
          if global:
            UnregisterHotKey(0, id.int32)
          else:
            1

        if ret != 1:
          plg.ctx.notify(plg.ctx, strformat.`&`("Failed to unregister hotkey {hotkey}"))
        else:
          window.hotkeys.del(id)

proc execPopup(plg: var Plugin) =
  let
    length = msg(plg.ctx, SCI_GETLENGTH, windowID = 0)
  if length != 0:
    var
      data = alloc0(length+1)
    defer: data.dealloc()

    if msg(plg.ctx, SCI_GETTEXT, length+1, data, 0) == length:
      plg.togglePopup()
      discard plg.ctx.handleCommand(plg.ctx, ($cast[cstring](data)).strip())

proc setTitle(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()
    winid = window.current
  if plg.ctx.cmdParam.len != 0:
    SetWindowText(cast[HWND](window.frames[winid]), plg.ctx.cmdParam[0].cstring)

feudPluginLoad:
  var
    window = plg.getWindow()
    frame: HWND

  registerFrame()

  window.frames.add nil
  window.editors.add cast[pointer](createPopup())

  frame = createFrame(show=false)
  window.frames.add cast[pointer](frame)
  window.editors.add cast[pointer](createWindow(frame, show=false))

  frame = createFrame()
  window.frames.add cast[pointer](frame)
  window.editors.add cast[pointer](createWindow(frame))
  frame.resizeFrame()
  window.current = 2
  msg(plg.ctx, SCI_GRABFOCUS)

  window.hotkeys = newTable[int, tuple[hotkey, callback: string]]()
  window.last = getTime()

  plg.ctx.msg = msg

  discard plg.ctx.handleCommand(plg.ctx, "setTheme")
  discard plg.ctx.handleCommand(plg.ctx, "setPopupTheme")

feudPluginTick:
  var
    msg: MSG
    lpmsg = cast[LPMSG](addr msg)
    window = plg.getWindow()

  if PeekMessageW(lpmsg, 0, 0, 0, PM_REMOVE) > 0:
    window.last = getTime()
    if msg.message == WM_HOTKEY:
      let
        id = msg.wparam.int
      if window.hotkeys.hasKey(id):
        discard plg.ctx.handleCommand(plg.ctx, window.hotkeys[id].callback)
    elif msg.message == WM_KEYDOWN:
      let
        hwnd = cast[pointer](msg.hwnd)
      if msg.wparam in [VK_ESCAPE, VK_RETURN] and hwnd == window.editors[0]:
        if msg.wparam == VK_ESCAPE:
          plg.togglePopup()
        elif msg.wparam == VK_RETURN:
          plg.execPopup()
      elif hwnd in window.editors:
        var
          id = msg.wparam.int shl 8
        if VK_MENU.GetKeyState() < 0: # Alt
          id = id or MOD_ALT
        if VK_CONTROL.GetKeyState() < 0:
          id = id or MOD_CONTROL
        if VK_SHIFT.GetKeyState() < 0:
          id = id or MOD_SHIFT
        if VK_LWIN.GetKeyState() < 0 or VK_RWIN.GetKeyState() < 0:
          id = id or MOD_WIN

        if window.hotkeys.hasKey(id):
          discard plg.ctx.handleCommand(plg.ctx, window.hotkeys[id].callback)
        else:
          discard TranslateMessage(addr msg)
          discard DispatchMessageW(addr msg)
    else:
      discard TranslateMessage(addr msg)
      discard DispatchMessageW(addr msg)

  if plg.ctx.tick mod 20 == 0:
    for i in countdown(window.editors.len-1, 0):
      if IsWindow(cast[HWND](window.editors[i])) == 0:
        DestroyWindow(cast[HWND](window.editors[i]))
        DestroyWindow(cast[HWND](window.frames[i]))
        window.setCurrentWindow(i)
        window.editors.delete(i)
        window.frames.delete(i)
    if window.editors.len == 2:
      discard plg.ctx.handleCommand(plg.ctx, "quit")

  if getTime() - window.last > initDuration(milliseconds=1):
    sleep(5)

feudPluginNotify:
  var
    params = plg.ctx.cmdParam.deepCopy()
  for param in params:
    msg(plg.ctx, SCI_APPENDTEXT, param.len+1, (param & "\n").cstring, windowid=1)

feudPluginUnload:
  var
    window = plg.getWindow()

  for i in countdown(window.editors.len-1, 0):
    DestroyWindow(cast[HWND](window.editors[i]))
    DestroyWindow(cast[HWND](window.frames[i]))
    window.setCurrentWindow(i)
    discard window.editors.pop()
    discard window.frames.pop()

  for id in window.hotkeys.keys():
    UnregisterHotKey(0, id.int32)

  unregisterFrame()

  freePlgData[Window](plg)

  plg.ctx.msg = nil
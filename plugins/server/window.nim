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
    history: seq[string]
    currHist: int

proc getWindow(plg: var Plugin): Window {.inline.} =
  return getPlgData[Window](plg)

proc getPlugin(ctx: var Ctx): Plugin =
  for pl in ctx.plugins.keys():
    if pl == currentSourcePath.splitFile().name:
      return ctx.plugins[pl]

proc msg*(ctx: var Ctx, msgID: int, wparam: pointer = nil, lparam: pointer = nil, windowID = -1): int {.discardable.} =
  var
    plg = ctx.getPlugin()
    window = plg.getWindow()

  let
    winid =
      if windowID == -1:
        window.current
      else:
        windowID

  if windowID > window.editors.len-1:
    return -1
  return SendMessage(cast[HWND](window.editors[winid]), cast[UINT](msgID), cast[WPARAM](wparam), cast[LPARAM](lparam))

proc setFocus(hwnd: HWND) =
  let
    editor = hwnd.GetWindow(GW_CHILD)

  if editor != 0:
    discard SendMessage(editor, SCI_GRABFOCUS, 0, 0)

proc getWinidFromHwnd(plg: var Plugin, hwnd: HWND): int =
  var
    window = plg.getWindow()

  result = window.frames.find(hwnd)
  if result == -1:
    result = window.editors.find(hwnd)

proc setCurrentWindow(plg: var Plugin, hwnd: HWND) =
  var
    window = plg.getWindow()
    winid = plg.getWinidFromHwnd(hwnd)

  if winid != -1:
    window.current = winid

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
  var
    plg = cast[Plugin](hwnd.GetWindowLongPtr(GWLP_USERDATA))

  case msg:
    of WM_ACTIVATE:
      hwnd.setFocus()
      plg.setCurrentWindow(hwnd)
    of WM_CREATE:
      var
        pCreate = cast[ptr CREATESTRUCT](lParam)
        plg = cast[LONG_PTR](pCreate.lpCreateParams)
      hwnd.SetWindowLongPtr(GWLP_USERDATA, plg)
    of WM_CLOSE:
      hwnd.DestroyWindow()
    of WM_DESTROY:
      PostQuitMessage(0)
    of WM_SIZE:
      hwnd.resizeFrame()
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
  wc.lpszClassName = "FeudFrame"
  # wc.hIcon         = LoadIcon(NULL, IDI_APPLICATION);
  # wc.hIconSm       = LoadIcon(NULL, IDI_APPLICATION);

  doException RegisterClassEx(addr wc) != 0, "Frame registration failed with " & $GetLastError()

proc unregisterFrame() =
  doException UnregisterClass("FeudFrame", GetModuleHandleW(nil)) != 0, "Frame unregistration failed with " & $GetLastError()

proc createFrame(plg: var Plugin, show = true): HWND =
  result = CreateWindowEx(
    WS_EX_OVERLAPPEDWINDOW, "FeudFrame", "", WS_OVERLAPPEDWINDOW,
    10, 10, 1200, 800, 0, 0, GetModuleHandleW(nil), cast[LPVOID](plg))

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
      verbose = "-v " in param
      spl = param.replace("-v ", "").split(" ", maxsplit=3)

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

    if verbose:
      plg.ctx.notify(plg.ctx, "Returned: " & $ret)

proc setCurrentWindowOnClose(plg: var Plugin, closeid: int) =
  var
    window = plg.getWindow()

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
    frame = plg.createFrame(show=false)

  window.frames.add cast[pointer](frame)
  window.editors.add cast[pointer](createWindow(frame))
  frame.resizeFrame()
  frame.ShowWindow(SW_SHOW)
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
    plg.setCurrentWindowOnClose(winid)
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

proc getPrevHistory(plg: var Plugin) =
  var
    window = plg.getWindow()

  if window.history.len != 0 and window.currHist > -1:
    discard msg(plg.ctx, SCI_SETTEXT, 0, window.history[window.currHist].cstring, 0)
    discard msg(plg.ctx, SCI_GOTOPOS, window.history[window.currHist].len, 0, 0)
    window.currHist -= 1

proc getNextHistory(plg: var Plugin) =
  var
    window = plg.getWindow()

  if window.history.len != 0 and window.currHist < window.history.len-2:
    if window.currHist == -1:
      window.currHist = 1
    else:
      window.currHist += 1
    discard msg(plg.ctx, SCI_SETTEXT, 0, window.history[window.currHist].cstring, 0)
    discard msg(plg.ctx, SCI_GOTOPOS, window.history[window.currHist].len, 0, 0)

proc addHistory(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()

  for param in plg.ctx.cmdParam:
    let
      param = param.strip()
    if param.len != 0:
      window.history.add param

  window.currHist = window.history.len-1

proc listHistory(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()
    nf = ""

  for cmd in window.history:
    nf &= cmd & "\n"

  if nf.len != 1:
    nf &= $window.currHist
    plg.ctx.notify(plg.ctx, nf)

proc execPopup(plg: var Plugin) =
  let
    length = msg(plg.ctx, SCI_GETLENGTH, windowID = 0)
  if length != 0:
    var
      data = alloc0(length+1)
    defer: data.dealloc()

    if msg(plg.ctx, SCI_GETTEXT, length+1, data, 0) == length:
      plg.togglePopup()
      let
        cmd = ($cast[cstring](data)).strip()
      if cmd.len != 0:
        plg.ctx.cmdParam = @[cmd]
        plg.addHistory()
        discard plg.ctx.handleCommand(plg.ctx, cmd)

proc setTitle(plg: var Plugin) {.feudCallback.} =
  var
    window = plg.getWindow()
    winid = window.current
  if plg.ctx.cmdParam.len != 0:
    SetWindowText(cast[HWND](window.frames[winid]), plg.ctx.cmdParam[0].cstring)

feudPluginDepends(["config"])

feudPluginLoad:
  var
    window = plg.getWindow()
    frame: HWND

  registerFrame()

  window.frames.add nil
  window.editors.add cast[pointer](createPopup())

  frame = plg.createFrame(show=false)
  window.frames.add cast[pointer](frame)
  window.editors.add cast[pointer](createWindow(frame, show=false))

  frame = plg.createFrame(show=false)
  window.frames.add cast[pointer](frame)
  window.editors.add cast[pointer](createWindow(frame))
  frame.resizeFrame()
  frame.ShowWindow(SW_SHOW)
  window.current = 2
  msg(plg.ctx, SCI_GRABFOCUS)

  window.hotkeys = newTable[int, tuple[hotkey, callback: string]]()
  window.last = getTime()

  plg.ctx.msg = msg

  discard plg.ctx.handleCommand(plg.ctx, "runHook postWindowLoad")

feudPluginTick:
  var
    msg: MSG
    lpmsg = cast[LPMSG](addr msg)
    window = plg.getWindow()
    done = false

  if PeekMessageW(lpmsg, 0, 0, 0, PM_REMOVE) > 0:
    window.last = getTime()
    if msg.message == WM_HOTKEY:
      let
        id = msg.wparam.int
      if window.hotkeys.hasKey(id):
        discard plg.ctx.handleCommand(plg.ctx, window.hotkeys[id].callback)
      done = true
    elif msg.message == WM_KEYDOWN:
      let
        hwnd = cast[pointer](msg.hwnd)
      if hwnd in window.editors:
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
          done = true
        elif hwnd == window.editors[0]:
          if msg.wparam == VK_ESCAPE:
            plg.togglePopup()
            window.currHist = window.history.len-1
            done = true
          elif msg.wparam == VK_RETURN:
            plg.execPopup()
            done = true
          elif msg.wparam == VK_UP:
            plg.getPrevHistory()
            done = true
          elif msg.wparam == VK_DOWN:
            plg.getNextHistory()
            done = true

    if not done:
      discard TranslateMessage(addr msg)
      discard DispatchMessageW(addr msg)

  if plg.ctx.tick mod 20 == 0:
    for i in countdown(window.editors.len-1, 0):
      if IsWindow(cast[HWND](window.editors[i])) == 0:
        DestroyWindow(cast[HWND](window.editors[i]))
        DestroyWindow(cast[HWND](window.frames[i]))
        plg.setCurrentWindowOnClose(i)
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

  discard plg.ctx.handleCommand(plg.ctx, "runHook preWindowUnload")

  for i in countdown(window.editors.len-1, 0):
    DestroyWindow(cast[HWND](window.editors[i]))
    DestroyWindow(cast[HWND](window.frames[i]))
    plg.setCurrentWindowOnClose(i)
    discard window.editors.pop()
    discard window.frames.pop()

  for id in window.hotkeys.keys():
    UnregisterHotKey(0, id.int32)

  unregisterFrame()

  freePlgData[Window](plg)

  plg.ctx.msg = nil
{.experimental: "codeReordering".}

import os, sets, strformat, strutils, tables, times

when defined(Windows):
  import winim/inc/[commctrl, windef, winbase, winuser], winim/winstr

import "../.."/src/pluginapi

const VKTable = {
  "F1": 112, "F2": 113, "F3": 114, "F4": 115, "F5": 116, "F6": 117, "F7": 118, "F8": 119, "F9": 120, "F10": 121,
  "F11": 122, "F12": 123, "F13": 124, "F14": 125, "F15": 126, "F16": 127, "F17": 128, "F18": 129, "F19": 130, "F20": 131,
  "F21": 132, "F22": 133, "F23": 134, "F24": 135, "Tab": 9, "PgDn": 34, "PgUp": 35, "Home": 36, "End": 35
}.toTable()

type
  Editor = ref object
    frame: HWND
    status: HWND
    editor: HWND
    popup: HWND
    docid: int
    last: int

  Windows = ref object
    last: Time
    current: int
    editors: seq[Editor]
    hotkeys: TableRef[int, tuple[hotkey, callback: string]]
    history: seq[string]
    currHist: int

    ecache: HashSet[HWND]
    pcache: HashSet[HWND]

proc getWindows(plg: var Plugin): Windows {.inline.} =
  return getPlgData[Windows](plg)

proc getPlugin(ctx: var Ctx): Plugin =
  let
    pl = "window"
  if ctx.plugins.hasKey(pl):
    return ctx.plugins[pl]

proc msg*(ctx: var Ctx, msgID: int, wparam: pointer = nil, lparam: pointer = nil, popup = false, windowID = -1): int {.discardable.} =
  var
    plg = ctx.getPlugin()
    windows = plg.getWindows()

  if windows.editors.len == 0:
    return

  let
    winid =
      if windowID == -1:
        windows.current
      else:
        windowID
    hwnd =
      if popup:
        windows.editors[winid].popup
      else:
        windows.editors[winid].editor

  if windowID > windows.editors.len-1:
    return -1
  return SendMessage(hwnd, cast[UINT](msgID), cast[WPARAM](wparam), cast[LPARAM](lparam)).int

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
    params = plg.getParam()

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
        if SciDefs.hasKey(spl[2]):
          w = SciDefs[spl[2]]
          ret = msg(plg.ctx, s, l, w.toPtr)
        else:
          if not spl[2].toInt(w):
            wc = spl[2].cstring
            ret = msg(plg.ctx, s, l, wc)
          else:
            ret = msg(plg.ctx, s, l, w.toPtr)
      else:
        ret = msg(plg.ctx, s, l)
    else:
      ret = msg(plg.ctx, s)

    plg.ctx.cmdParam = @[$ret]
    if verbose:
      plg.ctx.notify(plg.ctx, "Returned: " & $ret)

# Windows

proc setFocus(hwnd: HWND) =
  let
    editor = hwnd.GetWindow(GW_CHILD)

  if editor != 0:
    discard SendMessage(editor, SCI_GRABFOCUS, 0, 0)

proc getWinidFromHwnd(plg: var Plugin, hwnd: HWND): int =
  result = -1
  var
    windows = plg.getWindows()

  for i in 0 .. windows.editors.len-1:
    if hwnd in [windows.editors[i].frame, windows.editors[i].editor]:
      result = i
      break

proc getCurrentWindow(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()

  plg.ctx.cmdParam = @[$(windows.current)]

proc setCurrentWindow(plg: var Plugin, hwnd: HWND) =
  var
    windows = plg.getWindows()
    winid = plg.getWinidFromHwnd(hwnd)

  if winid != -1:
    windows.current = winid

proc resizeFrame(plg: var Plugin, hwnd: HWND) =
  let
    status = hwnd.GetDlgItem(hwnd.int32)
    editor = hwnd.GetWindow(GW_CHILD)

  if editor != 0:
    var
      rect: Rect
      srect: Rect

    if status != nil:
      status.SendMessage(WM_SIZE, 0, 0)
      status.GetWindowRect(addr srect)

    if hwnd.GetClientRect(addr rect) == 1:
      discard SetWindowPos(
        editor,
        HWND_TOP,
        rect.left,
        rect.top,
        rect.right-rect.left,
        rect.bottom-rect.top-(srect.bottom-srect.top),
        SWP_SHOWWINDOW)

      if status != nil:
        plg.setupStatus(status)

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
      plg.ctx.cmdParam = @[]
      plg.closeWindow()
    of WM_DESTROY:
      PostQuitMessage(0)
    of WM_NOTIFY:
      var
        notify = cast[ptr SCNotification](lParam)
        hdr = cast[ptr NMHDR](lParam)
      if hdr[].code == SCN_UPDATEUI:
        if (notify[].updated and SC_UPDATE_CONTENT) != 0:
          discard plg.ctx.handleCommand(plg.ctx, "runHook onWindowContent")
        elif (notify[].updated and SC_UPDATE_SELECTION) != 0:
          discard plg.ctx.handleCommand(plg.ctx, "runHook onWindowSelection")
    of WM_SIZE:
      plg.resizeFrame(hwnd)
      plg.positionPopup(hwnd.GetWindow(GW_CHILD).GetWindow(GW_CHILD))
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

proc createFrame(plg: var Plugin): HWND =
  result = CreateWindowEx(
    WS_EX_OVERLAPPEDWINDOW, "FeudFrame", "", WS_OVERLAPPEDWINDOW,
    10, 10, 1200, 800, 0, 0, GetModuleHandleW(nil), cast[LPVOID](plg))

  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

proc createStatus(parent: HWND): HWND =
  result = CreateWindowEx(
    0, STATUSCLASSNAME, nil, WS_CHILD or WS_VISIBLE or SBARS_SIZEGRIP, 0, 0, 0, 0,
    parent, parent, GetModuleHandleW(nil), nil)
  result.SendMessage(WM_SIZE, 0, 0)

proc setupStatus(plg: var Plugin, hwnd: HWND) =
  var
    srect: Rect
    splits = plg.getCbResult("get window:statusWidths").split(" ")
    intsplit: array[16, int32]
    count: int32
    total: int32

  if splits.len != 0 and hwnd.GetWindowRect(addr srect) == 1:
    for i in 0 .. 15:
      if i > splits.len-1:
        break
      try:
        total += splits[i].strip().parseInt().int32
        if total > 100:
          break
        intsplit[i] = (total * (srect.right - srect.left) / 100).int32
        count = (i + 1).int32
      except:
        return

    SendMessage(hwnd, SB_SETPARTS, cast[WPARAM](count), cast[LPARAM](addr intsplit))

proc setStatusBarHelper(plg: var Plugin, exec = false) =
  var
    windows = plg.getWindows()
    status = windows.editors[windows.current].status

  for param in plg.getParam():
    var
      (idstr, cmd) = param.splitCmd()
      id: int32

    if idstr.len != 0:
      try:
        id = idstr.parseInt().int32
      except:
        continue

      if exec:
        cmd = plg.getCbResult(cmd)

      SendMessage(status, SB_SETTEXTA, cast[WPARAM](id), cast[LPARAM](cmd.cstring))

proc setStatusBar(plg: var Plugin) {.feudCallback.} =
  plg.setStatusBarHelper()

proc setStatusBarCmd(plg: var Plugin) {.feudCallback.} =
  plg.setStatusBarHelper(exec = true)

proc createPopup(parent: HWND): HWND =
  result = CreateWindow("Scintilla", "", WS_CHILD, 10, 10, 800, 30, parent, 0, GetModuleHandleW(nil), nil)
  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  var
    style = result.GetWindowLong(GWL_STYLE)
  style = style and not WS_CAPTION
  result.SetWindowLong(GWL_STYLE, style)

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

proc createWindow(parent: HWND = 0, name = ""): HWND =
  result = CreateWindow("Scintilla", name, WS_CHILD, 0, 0, 1200, 800, parent, 0, GetModuleHandleW(nil), nil)
  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  result.ShowWindow(SW_SHOW)

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

proc setCurrentWindowOnClose(plg: var Plugin, closeid: int) =
  var
    windows = plg.getWindows()

  if closeid > 0:
    if closeid == windows.current:
      if closeid == windows.editors.len-1:
        windows.current = windows.current - 1
      else:
        windows.current = windows.current + 1
    else:
      if closeid < windows.current:
        windows.current -= 1

proc createEditor(plg: var Plugin): Editor =
  var
    windows = plg.getWindows()

  result = new(Editor)

  result.frame = plg.createFrame()
  result.editor = createWindow(result.frame)
  result.popup = createPopup(result.editor)
  if plg.getCbResult("get window:statusBar") == "true":
    result.status = createStatus(result.frame)
    plg.setupStatus(result.status)
  windows.editors.add result
  windows.current = windows.editors.len-1

  windows.ecache.incl result.editor
  windows.pcache.incl result.popup

proc deleteEditor(plg: var Plugin, winid: int) =
  var
    windows = plg.getWindows()

  if winid < windows.editors.len:
    windows.pcache.excl windows.editors[winid].popup
    windows.ecache.excl windows.editors[winid].editor

    DestroyWindow(windows.editors[winid].popup)
    DestroyWindow(windows.editors[winid].editor)
    DestroyWindow(windows.editors[winid].frame)
    plg.setCurrentWindowOnClose(winid)
    windows.editors.delete(winid)

    if windows.editors.len != 0:
      msg(plg.ctx, SCI_GRABFOCUS)

proc newWindow(plg: var Plugin) {.feudCallback.} =
  var
    editor = plg.createEditor()

  editor.frame.ShowWindow(SW_SHOW)
  msg(plg.ctx, SCI_GRABFOCUS)

  discard plg.ctx.handleCommand(plg.ctx, "runHook postNewWindow")

proc closeWindow(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()
    winid = 0
    params =
      if plg.ctx.cmdParam.len != 0:
        plg.getParam()
      else:
        @[$(windows.current)]

  for param in params:
    try:
      winid = param.parseInt()
    except:
      continue

    discard plg.ctx.handleCommand(plg.ctx, strformat.`&`("runHook preCloseWindow {winid}"))

    if winid > 0:
      plg.deleteEditor(winid)

proc setTitle(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()
    winid = windows.current
  if plg.ctx.cmdParam.len != 0:
    SetWindowText(windows.editors[winid].frame, plg.ctx.cmdParam[0].cstring)

# Hotkey

proc hotkey(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()
  if plg.ctx.cmdParam.len == 0:
    var hout = ""

    for hotkey in windows.hotkeys.keys():
      hout &= windows.hotkeys[hotkey].hotkey & " = " & windows.hotkeys[hotkey].callback & "\n"

    if hout.len != 0:
      plg.ctx.notify(plg.ctx, hout[0 .. ^2])
  else:
    for param in plg.getParam():
      let
        (hotkey, val) = param.splitCmd()

      var
        global = false
        fsModifiers: UINT
        vk: char
        spec = ""
        id = 0
        ret = 0

      for i in 0 .. hotkey.len-1:
        case hotkey[i]:
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
            if spec.len != 0 or i != hotkey.len-1:
              spec &= hotkey[i]
            else:
              vk = hotkey[i].toUpperAscii

      if spec.len != 0:
        if VKTable.hasKey(spec):
          vk = VKTable[spec].char
        else:
          plg.ctx.notify(plg.ctx, strformat.`&`("Invalid key '{spec}' specified for hotkey"))
          return

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
          windows.hotkeys[id] = (hotkey, val)
      else:
        ret =
          if global:
            UnregisterHotKey(0, id.int32)
          else:
            1

        if ret != 1:
          plg.ctx.notify(plg.ctx, strformat.`&`("Failed to unregister hotkey {hotkey}"))
        else:
          windows.hotkeys.del(id)

# History

proc getPrevHistory(plg: var Plugin) =
  var
    windows = plg.getWindows()

  if windows.history.len != 0 and windows.currHist > -1:
    discard msg(plg.ctx, SCI_SETTEXT, 0, windows.history[windows.currHist].cstring, popup=true)
    discard msg(plg.ctx, SCI_GOTOPOS, windows.history[windows.currHist].len, 0.toPtr, popup=true)
    windows.currHist -= 1

proc getNextHistory(plg: var Plugin) =
  var
    windows = plg.getWindows()

  if windows.history.len != 0 and windows.currHist < windows.history.len-2:
    if windows.currHist == -1:
      windows.currHist = 1
    else:
      windows.currHist += 1
    discard msg(plg.ctx, SCI_SETTEXT, 0, windows.history[windows.currHist].cstring, popup=true)
    discard msg(plg.ctx, SCI_GOTOPOS, windows.history[windows.currHist].len, 0.toPtr, popup=true)

proc addHistory(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()

  for param in plg.ctx.cmdParam:
    let
      param = param.strip()
    if param.len != 0:
      windows.history.add param

  windows.currHist = windows.history.len-1

proc listHistory(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()
    nf = ""

  for cmd in windows.history:
    nf &= cmd & "\n"

  if nf.len != 1:
    nf &= $windows.currHist
    plg.ctx.notify(plg.ctx, nf)

# Popup

proc positionPopup(plg: var Plugin, hwnd: HWND) =
  var
    ehwnd = hwnd.GetParent
    rect: RECT
    pix = msg(plg.ctx, SCI_TEXTHEIGHT, popup=true).int32

  if ehwnd.GetClientRect(addr rect) == 1:
    let
      width = ((rect.right-rect.left).float / 2).int32
      offset = ((rect.right-width) / 2).int32

    discard hwnd.SetWindowPos(
      HWND_TOP,
      offset,
      ((rect.bottom-rect.top) / 2).int32,
      width,
      pix,
      if hwnd.IsWindowVisible == 1: SWP_SHOWWINDOW else: 0)

proc togglePopup(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()
    hwnd = windows.editors[windows.current].popup

  if hwnd.IsWindowVisible() == 1:
    msg(plg.ctx, SCI_CLEARALL, popup=true)
    hwnd.ShowWindow(SW_HIDE)
    msg(plg.ctx, SCI_GRABFOCUS)
  else:
    plg.positionPopup(hwnd)
    if plg.ctx.cmdParam.len != 0:
      let
        param = plg.ctx.cmdParam[0]
      msg(plg.ctx, SCI_APPENDTEXT, param.len+1, (param & " ").cstring, popup=true)
      msg(plg.ctx, SCI_GOTOPOS, param.len+1, popup=true)

    msg(plg.ctx, SCI_MARKERDEFINE, 1, SC_MARK_ARROWS.toPtr, popup=true)
    msg(plg.ctx, SCI_MARKERADD, 0, 1.toPtr, popup=true)
    msg(plg.ctx, SCI_GRABFOCUS, popup=true)

    hwnd.ShowWindow(SW_SHOW)

proc execPopup(plg: var Plugin) =
  let
    length = msg(plg.ctx, SCI_GETLENGTH, popup=true)
  if length != 0:
    var
      data = alloc0(length+1)
    defer: data.dealloc()

    if msg(plg.ctx, SCI_GETTEXT, length+1, data, popup=true) == length:
      plg.togglePopup()
      let
        cmd = ($cast[cstring](data)).strip()
      if cmd.len != 0:
        plg.ctx.cmdParam = @[cmd]
        plg.addHistory()
        discard plg.ctx.handleCommand(plg.ctx, cmd)

proc getLastId(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()
    winid = windows.current

  plg.ctx.cmdParam = @[$windows.editors[winid].last]

proc getDocId(plg: var Plugin) {.feudCallback.} =
  var
    windows = plg.getWindows()
    winid = windows.current

  if plg.ctx.cmdParam.len != 0:
    try:
      winid = plg.ctx.cmdParam[0].parseInt()
      plg.ctx.cmdParam = @[$windows.editors[winid].docid]
    except:
      plg.ctx.cmdParam = @["-1"]
  else:
    plg.ctx.cmdParam = @[$windows.editors[winid].docid]

proc setDocId(plg: var Plugin) {.feudCallback.} =
  if plg.ctx.cmdParam.len != 0:
    var
      windows = plg.getWindows()
      winid = windows.current
      docid = -1

    try:
      docid = plg.ctx.cmdParam[0].parseInt()
      windows.editors[winid].last = windows.editors[winid].docid
      windows.editors[winid].docid = docid
    except:
      discard

feudPluginDepends(["config"])

feudPluginLoad:
  var
    windows = plg.getWindows()

  windows.ecache.init()
  windows.pcache.init()

  registerFrame()

  plg.ctx.msg = msg

  discard plg.createEditor()

  windows.hotkeys = newTable[int, tuple[hotkey, callback: string]]()
  windows.last = getTime()

  discard plg.ctx.handleCommand(plg.ctx, "hook onReady newWindow")
  discard plg.ctx.handleCommand(plg.ctx, "runHook postWindowLoad")

feudPluginTick:
  var
    msg: MSG
    lpmsg = cast[LPMSG](addr msg)
    windows = plg.getWindows()
    done = false

  if PeekMessageW(lpmsg, 0, 0, 0, PM_REMOVE) > 0:
    windows.last = getTime()
    if msg.message == WM_HOTKEY:
      let
        id = msg.wparam.int
      if windows.hotkeys.hasKey(id):
        discard plg.ctx.handleCommand(plg.ctx, windows.hotkeys[id].callback)
      done = true
    elif msg.message == WM_KEYDOWN:
      if msg.hwnd in windows.ecache or msg.hwnd in windows.pcache:
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

        if windows.hotkeys.hasKey(id):
          discard plg.ctx.handleCommand(plg.ctx, windows.hotkeys[id].callback)
          done = true
        elif msg.hwnd in windows.pcache:
          if msg.wparam == VK_ESCAPE:
            plg.togglePopup()
            windows.currHist = windows.history.len-1
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
    for i in countdown(windows.editors.len-1, 0):
      if IsWindow(windows.editors[i].frame) == 0:
        plg.deleteEditor(i)
    if plg.ctx.ready == true and windows.editors.len == 1:
      plg.deleteEditor(0)
      discard plg.ctx.handleCommand(plg.ctx, "quit")

  if getTime() - windows.last > initDuration(milliseconds=1):
    sleep(5)

feudPluginNotify:
  var
    windows = plg.getWindows()

  for param in plg.getParam():
    msg(plg.ctx, SCI_APPENDTEXT, param.len+1, (param & "\n").cstring, windowID=0)
    if windows.editors.len != 0 and windows.current < windows.editors.len:
      discard plg.ctx.handleCommand(plg.ctx, strformat.`&`("runHook postWindowNotify {param.strip()}"))

feudPluginUnload:
  var
    windows = plg.getWindows()

  discard plg.ctx.handleCommand(plg.ctx, "runHook preWindowUnload")

  for i in countdown(windows.editors.len-1, 0):
    plg.deleteEditor(i)

  for id in windows.hotkeys.keys():
    UnregisterHotKey(0, id.int32)

  unregisterFrame()

  freePlgData[Windows](plg)

  plg.ctx.msg = nil
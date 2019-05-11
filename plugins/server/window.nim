{.experimental: "codeReordering".}

import os, sets, strformat, strutils, tables, times

when defined(Windows):
  import winim/inc/[commctrl, shellapi, windef, winbase, winuser], winim/winstr

import "../.."/src/pluginapi

include "."/window/frame
include "."/window/status
include "."/window/popup
include "."/window/editor
include "."/window/hotkey
include "."/window/history

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
    var
      spl = param.parseCmdLine()
      verbose = "-v" in spl
      popup = "-p" in spl

    if verbose:
      spl.delete(spl.find("-v"))
    if popup:
      spl.delete(spl.find("-p"))

    var
      s, l, w: int
      wc: cstring
      ret: int

    if spl.len > 0:
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
          ret = msg(plg.ctx, s, l, w.toPtr, popup = popup)
        else:
          if not spl[2].toInt(w):
            wc = spl[2].cstring
            ret = msg(plg.ctx, s, l, wc, popup = popup)
          else:
            ret = msg(plg.ctx, s, l, w.toPtr, popup = popup)
      else:
        ret = msg(plg.ctx, s, l, popup = popup)
    else:
      ret = msg(plg.ctx, s, popup = popup)

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

proc createWindow(parent: HWND = 0, name = ""): HWND =
  result = CreateWindow("Scintilla", name, WS_CHILD, 0, 0, 1200, 800, parent, 0, GetModuleHandleW(nil), nil)
  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  result.DragAcceptFiles(1)
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

proc getDroppedFiles(hDrop: HDROP): seq[string] =
  var
    numFiles = hDrop.DragQueryFileA(cast[UINT](0xFFFFFFFF), nil, 0).int
    data = alloc0(8192)
    size: UINT
  defer: data.dealloc()

  for i in 0 .. numFiles-1:
    size = hDrop.DragQueryFileA(cast[UINT](i), cast[LPSTR](data), 8192)
    if size.int != 0:
      result.add $cast[cstring](data)

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

  if not plg.ctx.ready:
    discard plg.ctx.handleCommand(plg.ctx, "hook onReady newWindow")
  else:
    plg.newWindow()
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
    elif msg.message == WM_DROPFILES:
      let
        files = getDroppedFiles(cast[HDROP](msg.wparam))
      if files.len != 0:
        discard plg.ctx.handleCommand(plg.ctx, "open \"" & files.join("\" \"") & "\"")

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
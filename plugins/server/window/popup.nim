proc createPopup(parent: HWND): HWND =
  result = CreateWindow("Scintilla", "", WS_CHILD, 10, 10, 800, 30, parent, 0, GetModuleHandleW(nil), nil)
  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  var
    style = result.GetWindowLong(GWL_STYLE)
  style = style and not WS_CAPTION
  result.SetWindowLong(GWL_STYLE, style)

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

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

proc popupGrabFocus(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    windows = plg.getWindows()
    hwnd = windows.editors[windows.current].popup

  if hwnd.IsWindowVisible() == 1:
    msg(plg.ctx, SCI_GRABFOCUS, popup=true)

proc closePopup(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    windows = plg.getWindows()
    hwnd = windows.editors[windows.current].popup

  if hwnd.IsWindowVisible() == 1:
    msg(plg.ctx, SCI_CLEARALL, popup=true)
    hwnd.ShowWindow(SW_HIDE)
    msg(plg.ctx, SCI_GRABFOCUS)

proc togglePopup(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    windows = plg.getWindows()
    hwnd = windows.editors[windows.current].popup

  if hwnd.IsWindowVisible() == 1:
    plg.closePopup(cmd)
  else:
    plg.positionPopup(hwnd)
    if cmd.params.len != 0:
      let
        param = cmd.params.join(" ") & " "
      msg(plg.ctx, SCI_APPENDTEXT, param.len, param.cstring, popup=true)
      msg(plg.ctx, SCI_GOTOPOS, param.len, popup=true)
      msg(plg.ctx, SCI_SCROLLRANGE, 1, 0.toPtr, popup=true)

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
      cmd: CmdData
    defer: data.dealloc()

    if msg(plg.ctx, SCI_GETTEXT, length+1, data, popup=true) == length:
      cmd = new(CmdData)
      plg.togglePopup(cmd)
      let
        command = ($cast[cstring](data)).strip()
      if command.len != 0:
        cmd = newCmdData(command)
        plg.addHistory(cmd)
        plg.ctx.handleCommand(plg.ctx, cmd)

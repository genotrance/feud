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
    defer: data.dealloc()

    if msg(plg.ctx, SCI_GETTEXT, length+1, data, popup=true) == length:
      plg.togglePopup()
      let
        cmd = ($cast[cstring](data)).strip()
      if cmd.len != 0:
        plg.ctx.cmdParam = @[cmd]
        plg.addHistory()
        discard plg.ctx.handleCommand(plg.ctx, cmd)

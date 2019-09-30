proc resizeFrame(plg: Plugin, hwnd: HWND) =
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
    ccmd: CmdData

  case msg:
    of WM_ACTIVATE:
      hwnd.setFocus()
      plg.setCurrentWindow(hwnd)
      ccmd = newCmdData("runHook onWindowActivate")
      plg.ctx.handleCommand(plg.ctx, ccmd)
    of WM_CREATE:
      var
        pCreate = cast[ptr CREATESTRUCT](lParam)
        plg = cast[LONG_PTR](pCreate.lpCreateParams)
      hwnd.SetWindowLongPtr(GWLP_USERDATA, plg)
    of WM_CLOSE:
      ccmd = new(CmdData)
      plg.closeWindow(ccmd)
    of WM_DESTROY:
      PostQuitMessage(0)
    of WM_NOTIFY:
      var
        notify = cast[ptr SCNotification](lParam)
        hdr = cast[ptr NMHDR](lParam)
      if hdr[].code == SCN_UPDATEUI:
        ccmd = newCmdData("runHook onWindowUpdate")
        plg.ctx.handleCommand(plg.ctx, ccmd)
        if (notify[].updated and SC_UPDATE_CONTENT) != 0:
          ccmd = newCmdData("runHook onWindowContent")
          plg.ctx.handleCommand(plg.ctx, ccmd)
        elif (notify[].updated and SC_UPDATE_SELECTION) != 0:
          ccmd = newCmdData("runHook onWindowSelection")
          plg.ctx.handleCommand(plg.ctx, ccmd)
      elif hdr[].code in [SCN_SAVEPOINTREACHED, SCN_SAVEPOINTLEFT]:
        ccmd = newCmdData("runHook onWindowSavePoint")
        plg.ctx.handleCommand(plg.ctx, ccmd)
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

proc createFrame(plg: Plugin): HWND =
  result = CreateWindowEx(
    WS_EX_OVERLAPPEDWINDOW, "FeudFrame", "", WS_OVERLAPPEDWINDOW,
    10, 10, 1200, 800, 0, 0, GetModuleHandleW(nil), cast[LPVOID](plg))

  doException result.IsWindow() != 0, "IsWindow() failed with " & $GetLastError()

  doException result.UpdateWindow() != 0, "UpdateWindow() failed with " & $GetLastError()

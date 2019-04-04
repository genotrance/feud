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

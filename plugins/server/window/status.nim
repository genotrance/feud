proc createStatus(parent: HWND): HWND =
  result = CreateWindowEx(
    0, STATUSCLASSNAME, nil, WS_CHILD or WS_VISIBLE or SBARS_SIZEGRIP, 0, 0, 0, 0,
    parent, parent, GetModuleHandleW(nil), nil)
  result.SendMessage(WM_SIZE, 0, 0)

proc setupStatus(plg: Plugin, hwnd: HWND) =
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

proc setStatusBarHelper(plg: Plugin, cmd: CmdData, exec = false) =
  var
    windows = plg.getWindows()
    status = windows.editors[windows.current].status

  if cmd.params.len > 1:
    var
      idstr = cmd.params[0]
      command = cmd.params[1 .. ^1].join(" ")
      id: int32

    try:
      id = idstr.parseInt().int32
    except:
      return

    if exec:
      command = plg.getCbResult(command)

    SendMessage(status, SB_SETTEXTA, cast[WPARAM](id), cast[LPARAM](command.cstring))

proc setStatusBar(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  plg.setStatusBarHelper(cmd)

proc setStatusBarCmd(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  plg.setStatusBarHelper(cmd, exec = true)

proc getPosition(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  let
    pos = plg.ctx.msg(plg.ctx, SCI_GETCURRENTPOS)
    line = plg.ctx.msg(plg.ctx, SCI_LINEFROMPOSITION, pos) + 1
    col = plg.ctx.msg(plg.ctx, SCI_GETCOLUMN, pos) + 1

  cmd.returned.add strformat.`&`("R{line} : C{col}")

proc getDocSize(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  var
    length = plg.ctx.msg(plg.ctx, SCI_GETLENGTH)
    lstr = ""

  if length < 1024:
    lstr = $length
  elif length < 1024 * 1024:
    lstr = strformat.`&`("{(length / 1024):.2f} KB")
  elif length < 1024 * 1024 * 1024:
    lstr = strformat.`&`("{(length / 1024 / 1024):.2f} MB")
  else:
    lstr = strformat.`&`("{(length / 1024 / 1024 / 1024):.2f} GB")

  cmd.returned.add lstr

proc getRatio(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  let
    pos = plg.ctx.msg(plg.ctx, SCI_GETCURRENTPOS)
    length = plg.ctx.msg(plg.ctx, SCI_GETLENGTH)

  cmd.returned.add(
    if length != 0:
      strformat.`&`("{(pos / length) * 100:3.2f}%")
    else:
      ""
  )

proc getModified(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  cmd.returned.add(
    if plg.ctx.msg(plg.ctx, SCI_GETMODIFY) == 0:
      ""
    else:
      "***"
  )
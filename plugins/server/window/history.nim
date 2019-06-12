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

proc addHistory(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    windows = plg.getWindows()

  if cmd.params.len != 0:
    windows.history.add cmd.params.join(" ")

  windows.currHist = windows.history.len-1

proc listHistory(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    windows = plg.getWindows()
    nf = ""

  for cmd in windows.history:
    nf &= cmd & "\n"

  if nf.len != 1:
    nf &= $windows.currHist
    plg.ctx.notify(plg.ctx, nf)

proc createEditor(plg: Plugin): Editor =
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

proc deleteEditor(plg: Plugin, winid: int) =
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

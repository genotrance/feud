import deques, os, sets, strformat, strutils, tables, times

import "../.."/src/pluginapi
import "../.."/wrappers/fuzzy

const MAX_BUFFER = 8192

type
  Doc = ref object
    path: string
    docptr: pointer
    cursor: int
    firstLine: int
    syncTime: Time
    modified: bool
    windows: HashSet[int]

  Docs = ref object
    doclist: seq[Doc]
    dirHistory: Deque[string]
    currDir: int

proc getDocs(plg: var Plugin): Docs =
  return getCtxData[Docs](plg)

proc getDocId(plg: var Plugin, winid = -1): int =
  var
    cmd = "getDocId"
  if winid != -1:
    cmd &= &" {winid}"
  result = plg.getCbIntResult(cmd, -1)

proc setDocId(plg: var Plugin, docid: int) =
  var
    cmd = newCmdData(&"setDocId {docid}")
  plg.ctx.handleCommand(plg.ctx, cmd)

proc getDocPath(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()
    docid = plg.getDocId()

  if docid != -1:
    cmd.returned.add docs.doclist[docid].path

proc setCurrentDir(plg: var Plugin, dir: string) =
  var
    docs = plg.getDocs()

  let
    pdir = getCurrentDir()
  dir.setCurrentDir()
  let
    ndir = getCurrentDir()

  if pdir != ndir:
    if docs.currDir < docs.dirHistory.len-1:
      docs.dirHistory.shrink(fromLast = docs.dirHistory.len - docs.currDir - 1)

    docs.dirHistory.addLast(ndir)
    docs.currDir = docs.dirHistory.len - 1

proc findDocFromString(plg: var Plugin, srch: string): int =
  result = -1
  var
    docs = plg.getDocs()
    scores: seq[int]
    score: cint = 0

  # Exact match
  for i in 0 .. docs.doclist.len-1:
    let
      str = docs.doclist[i].path
    if srch == str:
      result = i
      break
    else:
      scores.add 0

  # File name.ext match
  if result == -1:
    for i in 0 .. docs.doclist.len-1:
      let
        str = docs.doclist[i].path.extractFilename()
      if srch == str:
        result = i
        break
      elif fuzzy_match(srch, str, score) and score > scores[i]:
          scores[i] = score

  # File name match
  if result == -1:
    for i in 0 .. docs.doclist.len-1:
      let
        str = docs.doclist[i].path.splitFile().name
      if srch == str:
        result = i
        break
      elif fuzzy_match(srch, str, score) and score > scores[i]:
          scores[i] = score

  # Fuzzy
  if result == -1:
    let
      maxf = max(scores)
    if maxf > 100:
      result = scores.find(maxf)

proc findDocFromParam(plg: var Plugin, param: string): int =
  var
    docs = plg.getDocs()

  result =
    if param.len == 0:
      plg.getDocId()
    else:
      plg.findDocFromString(param)

  if result < 0:
    try:
      result = parseInt(param)
    except ValueError:
      discard

  if result > docs.doclist.len-1:
    result = -1

proc switchDoc(plg: var Plugin, docid: int) =
  var
    docs = plg.getDocs()
    currDoc = plg.getDocId()
    currWindow = plg.getCbIntResult("getCurrentWindow", -1)
    cmd: CmdData

  if docid < 0 or docid > docs.doclist.len-1 or currWindow < 0 or currDoc < 0 or (docid == currDoc and docid != 0):
    return

  docs.doclist[currDoc].cursor = plg.ctx.msg(plg.ctx, SCI_GETCURRENTPOS)
  docs.doclist[currDoc].firstLine = plg.ctx.msg(plg.ctx, SCI_GETFIRSTVISIBLELINE)
  discard plg.ctx.msg(plg.ctx, SCI_ADDREFDOCUMENT, 0, docs.doclist[currDoc].docptr)
  docs.doclist[currDoc].windows.excl currWindow

  docs.doclist[docid].windows.incl currWindow
  discard plg.ctx.msg(plg.ctx, SCI_SETDOCPOINTER, 0, docs.doclist[docid].docptr)
  discard plg.ctx.msg(plg.ctx, SCI_RELEASEDOCUMENT, 0, docs.doclist[docid].docptr)
  discard plg.ctx.msg(plg.ctx, SCI_GOTOPOS, docs.doclist[docid].cursor)
  discard plg.ctx.msg(plg.ctx, SCI_SETFIRSTVISIBLELINE, docs.doclist[docid].firstLine)

  plg.setDocId(docid)

  cmd = newCmdData(&"setTitle {docs.doclist[docid].path}")
  plg.ctx.handleCommand(plg.ctx, cmd)

  let
    lexer = plg.getCbResult(&"setLexer {docs.doclist[docid].path}")
  if lexer.len != 0:
    cmd = newCmdData(&"setTheme {lexer}")
    plg.ctx.handleCommand(plg.ctx, cmd)

  if plg.getCbResult("get file:fileChdir") == "true":
    if docs.doclist[docid].path notin ["Notifications", "New document"]:
      docs.doclist[docid].path.parentDir().setCurrentDir()
    else:
      docs.dirHistory.peekFirst().setCurrentDir()

  if docid == 0:
    plg.gotoEnd()

  cmd = newCmdData("runHook postFileSwitch")
  plg.ctx.handleCommand(plg.ctx, cmd)

proc loadFileContents(plg: var Plugin, path: string) =
  if not fileExists(path):
    return

  discard plg.ctx.msg(plg.ctx, SCI_CLEARALL)
  var
    buffer = newString(MAX_BUFFER)
    bytesRead = 0
    f = open(path)

  while true:
    bytesRead = readBuffer(f, addr buffer[0], MAX_BUFFER)
    if bytesRead == MAX_BUFFER:
      discard plg.ctx.msg(plg.ctx, SCI_ADDTEXT, bytesRead, addr buffer[0])
    else:
      if bytesRead != 0:
        buffer.setLen(bytesRead)
        discard plg.ctx.msg(plg.ctx, SCI_ADDTEXT, bytesRead, addr buffer[0])
      break
  f.close()

  discard plg.ctx.msg(plg.ctx, SCI_SETSAVEPOINT)
  var
    cmd = newCmdData("runHook postFileLoad")
  plg.ctx.handleCommand(plg.ctx, cmd)

proc newDoc(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()
    doc = new(Doc)

  doc.windows.init()
  doc.path = "New document"
  doc.docptr = plg.ctx.msg(plg.ctx, SCI_CREATEDOCUMENT, 0.toPtr).toPtr

  docs.doclist.add doc

  plg.switchDoc(docs.doclist.len-1)

proc open(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  proc getDirPat(path: string): tuple[dir, pat: string] =
    if "/" in path or "\\" in path:
      result.dir = path.parentDir()
      result.pat = path.replace(result.dir, "")
      if result.pat[0] in ['\\', '/']:
        result.pat = result.pat[1 .. ^1]
    else:
      result.dir = getCurrentDir()
      result.pat = path

  proc openRec(plg: var Plugin, path: string) =
    var
      (dir, pat) = path.getDirPat()
      cmd = new(CmdData)
    for d in dir.walkDirRec(yieldFilter={pcDir}):
      if ".git" notin d:
        if "*" in pat or "?" in pat or fileExists(d/pat):
          cmd.params.add d/pat
    if cmd.params.len != 0:
      plg.open(cmd)

  proc openFuzzy(plg: var Plugin, path: string) =
    var
      (dir, pat) = path.getDirPat()
      bestscore = 0
      bestmatch = ""
      score: cint = 0
    for f in dir.walkDirRec():
      if ".git" notin f:
        if fuzzy_match(pat, f.extractFilename(), score):
          if score > bestscore:
            bestscore = score
            bestmatch = f
    if bestmatch.len != 0:
      if " " in bestmatch or "\t" in bestmatch:
        bestmatch = '"' & bestmatch & '"'
      var
        cmd = newCmdData(&"togglePopup open {bestmatch}")
      plg.ctx.handleCommand(plg.ctx, cmd)

  var
    sel = plg.getSelection()
    selected = false
    ccmd: CmdData

  if cmd.params.len == 0 and sel.len != 0:
    cmd.params.add sel
    selected = true

  if cmd.params.len == 0:
    ccmd = newCmdData("togglePopup open")
    plg.ctx.handleCommand(plg.ctx, ccmd)
  else:
    defer:
      selected = false

    var
      paths = cmd.params
      recurse = false
      fuzzy = false

    if "-r" in paths:
      recurse = true
      paths.delete(paths.find("-r"))

    if "-f" in paths:
      fuzzy = true
      paths.delete(paths.find("-f"))

    if paths.len == 0 and sel.len != 0:
      paths.add sel
      selected = true

    let
      togOpen = "togglePopup open" & (if recurse: " -r" elif fuzzy: " -f" else: "")
    if paths.len == 0:
      ccmd = newCmdData(togOpen)
      plg.ctx.handleCommand(plg.ctx, ccmd)

    for path in paths:
      let
        path = path.strip()

      if "*" in path or "?" in path:
        if not recurse:
          ccmd = new(CmdData)
          for spath in path.walkPattern():
            ccmd.params.add spath.expandFilename()
          if ccmd.params.len != 0:
            plg.open(ccmd)
        else:
          plg.openRec(path)
      elif path.len != 0:
        let
          docid = plg.findDocFromParam(path)
        if docid > -1:
          plg.switchDoc(docid)
        elif path.dirExists():
          ccmd = new(CmdData)
          for kind, file in path.walkDir():
            if kind == pcFile:
              ccmd.params.add file.expandFilename()
          if ccmd.params.len != 0:
            plg.open(ccmd)
        else:
          if not fileExists(path):
            if recurse:
              plg.openRec(path)
            elif fuzzy:
              plg.openFuzzy(path)
            else:
              if selected:
                ccmd = newCmdData(togOpen)
                plg.ctx.handleCommand(plg.ctx, ccmd)
              else:
                plg.ctx.notify(plg.ctx, &"File does not exist: {path}")
          else:
            var
              path = path.expandFilename()
              docs = plg.getDocs()
              info = path.getFileInfo()
              doc = new(Doc)

            doc.windows.init()
            doc.path = path
            doc.docptr = plg.ctx.msg(plg.ctx, SCI_CREATEDOCUMENT, info.size.toPtr).toPtr
            doc.syncTime = path.getLastModificationTime()

            docs.doclist.add doc

            plg.switchDoc(docs.doclist.len-1)

            plg.loadFileContents(path)

            discard plg.ctx.msg(plg.ctx, SCI_GOTOPOS, 0)

proc save(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()
    currDoc = plg.getDocId()

  if docs.doclist.len != 0 and currDoc > 0:
    let
      doc = docs.doclist[currDoc]

    if doc.path == "New document":
      plg.ctx.notify(plg.ctx, &"Save new document using saveAs <fullpath>")
      cmd.failed = true
      return

    discard plg.ctx.msg(plg.ctx, SCI_SETREADONLY, 1.toPtr)
    defer:
      discard plg.ctx.msg(plg.ctx, SCI_SETREADONLY, 0.toPtr)

    let
      data = cast[cstring](plg.ctx.msg(plg.ctx, SCI_GETCHARACTERPOINTER))

    try:
      var
        f = open(doc.path, fmWrite)
        ccmd: CmdData
      f.write(data)
      f.close()
      plg.ctx.notify(plg.ctx, &"Saved {doc.path}")

      doc.syncTime = doc.path.getLastModificationTime()

      discard plg.ctx.msg(plg.ctx, SCI_SETSAVEPOINT)
      ccmd = newCmdData(&"setTitle {doc.path}")
      plg.ctx.handleCommand(plg.ctx, ccmd)
    except:
      plg.ctx.notify(plg.ctx, &"Failed to save {doc.path}")
      cmd.failed = true

proc saveAs(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  if cmd.params.len != 0:
    var
      name = cmd.params[0].strip()
      docs = plg.getDocs()
      doc = docs.doclist[plg.getDocId()]

    if name.len != 0:
      doc.path = name
      if not doc.path.isAbsolute:
        doc.path = getCurrentDir() / name
      doc.path.normalizePath()

      if plg.getCbResult("get file:fileChdir") == "true":
        doc.path.parentDir().setCurrentDir()

      plg.save(cmd)

proc list(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    lout = ""
    docs = plg.getDocs()

  for i in 0 .. docs.doclist.len-1:
    lout &= &"{i}: {docs.doclist[i].path.extractFilename()}\n"

  plg.ctx.notify(plg.ctx, lout[0..^2])

proc close(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()

  if cmd.params.len == 0:
    cmd.params.add ""
  for param in cmd.params:
    var
      docid = plg.findDocFromParam(param)
      currDoc = plg.getDocId()

    if docid > 0 and currDoc > -1:
      if docid == currDoc:
        if docid == docs.doclist.len-1:
          plg.switchDoc(docid-1)
        else:
          plg.switchDoc(docid+1)

      if docs.doclist[docid].windows.len == 0:
        discard plg.ctx.msg(plg.ctx, SCI_RELEASEDOCUMENT, 0, docs.doclist[docid].docptr)
        docs.doclist.delete(docid)
        currDoc = plg.getDocId()
        if docid < currDoc:
          plg.setDocId(currDoc-1)

proc closeAll(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()

  while docs.doclist.len != 1:
    cmd.params.add $(docs.doclist.len-1)
    plg.close(cmd)

proc unload(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()

  for param in cmd.params:
    var
      winid: int
    try:
      winid = param.parseInt()
    except:
      winid = -1

    if winid != -1:
      let
        docid = plg.getDocId(winid)

      if docid < docs.doclist.len and docid > -1:
        discard plg.ctx.msg(plg.ctx, SCI_ADDREFDOCUMENT, 0, docs.doclist[docid].docptr, windowID=winid)
        docs.doclist[docid].windows.excl winid

        discard plg.ctx.msg(plg.ctx, SCI_SETDOCPOINTER, 0, nil, windowID=winid)

proc next(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()

  if docs.doclist.len != 1:
    var
      docid = plg.getDocId()
    docid += 1
    if docid == docs.doclist.len:
      docid = 0

    plg.switchDoc(docid)

proc prev(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()

  if docs.doclist.len != 1:
    var
      docid = plg.getDocId()
    docid -= 1
    if docid < 0:
      docid = docs.doclist.len-1

    plg.switchDoc(docid)

proc last(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()

  var
    last = plg.getCbIntResult("getLastId", -1)
  if last > docs.doclist.len-1:
    last = 0

  plg.switchDoc(last)

proc reload(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()
    docid = plg.getDocId()
    doc = docs.doclist[docid]

  if docid > 0:
    plg.loadFileContents(doc.path)

    doc.syncTime = doc.path.getLastModificationTime()

    plg.ctx.notify(plg.ctx, &"Reloaded {doc.path}")

proc reloadAll(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()

  plg.reload(cmd)
  if docs.doclist.len != 2:
    for i in 0 .. docs.doclist.len-1:
      plg.next(cmd)
      plg.reload(cmd)

proc reloadIfChanged(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()
    docid = plg.getDocId()
    doc = docs.doclist[docid]

  if doc.path.fileExists() and doc.syncTime < doc.path.getLastModificationTime():
    if plg.ctx.msg(plg.ctx, SCI_GETMODIFY) == 0:
      plg.reload(cmd)
    else:
      plg.ctx.notify(plg.ctx, &"File '{doc.path.extractFilename()}' with unsaved modifications changed behind the scenes")

proc checkIfAnyModified(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()

  cmd.failed = true
  for i in 1 .. docs.doclist.len-1:
    if docs.doclist[i].modified:
      cmd.failed = false
      break

proc updateModified(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()
    docid = plg.getDocId()
    doc = docs.doclist[docid]

  if plg.ctx.msg(plg.ctx, SCI_GETMODIFY) == 0:
    doc.modified = false
  else:
    doc.modified = true

proc cd(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    docs = plg.getDocs()

  if cmd.params.len != 0:
    if cmd.params[0].len != 0:
      let
        path = cmd.params[0].strip()

      if path.dirExists():
        plg.setCurrentDir(path)
      elif path.fileExists():
        plg.setCurrentDir(path.parentDir())
      elif path == "$":
        var
          docid = plg.getDocId()

        if docid > -1 and docid < docs.doclist.len:
          cmd.params = @[docs.doclist[docid].path]
          plg.cd(cmd)
      elif path == "-":
        if docs.currDir != 0:
          docs.currDir -= 1
          docs.dirHistory[docs.currDir].setCurrentDir()
      elif path == "+":
        if docs.currDir < docs.dirHistory.len-1:
          docs.currDir += 1
          docs.dirHistory[docs.currDir].setCurrentDir()
      else:
        plg.ctx.notify(plg.ctx, "Directory doesn't exist: " & path)
        return

  plg.ctx.notify(plg.ctx, "Current directory: " & getCurrentDir())

feudPluginDepends(["filetype", "theme", "window"])

feudPluginLoad:
  var
    docs = plg.getDocs()

  if docs.doclist.len == 0:
    var
      notif = new(Doc)
    notif.windows.init()
    notif.path = "Notifications"
    notif.docptr = plg.ctx.msg(plg.ctx, SCI_GETDOCPOINTER, windowID=0).toPtr
    notif.windows.incl 0

    docs.doclist.add notif
    plg.setDocId(0)

    docs.dirHistory = initDeque[string]()
    docs.dirHistory.addLast(getCurrentDir())

  for i in [
    "hook preCloseWindow unload",
    "hook onWindowActivate reloadIfChanged",
    "hook postFileSwitch reloadIfChanged",
    "hook postNewWindow open 0",
    "hook onWindowSavePoint updateModified"
  ]:
    var
      ccmd = newCmdData(i)
    plg.ctx.handleCommand(plg.ctx, ccmd)
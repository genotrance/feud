import os, segfaults, sequtils, strformat, strutils, tables

import "../.."/src/pluginapi
import "../.."/wrappers/fuzzy

const MAX_BUFFER = 8192

type
  Doc = ref object
    path: string
    docptr: pointer
    cursor: int

  Docs = ref object
    current: int
    doclist: seq[Doc]

proc getDocs(plg: var Plugin): Docs =
  return getCtxData[Docs](plg)

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
    elif fuzzy_match(srch, str, score):
      scores.add score
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
      docs.current
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

  if docid < 0 or docid > docs.doclist.len-1 or docid == docs.current:
    return

  docs.doclist[docs.current].cursor = plg.ctx.msg(plg.ctx, SCI_GETCURRENTPOS)
  discard plg.ctx.msg(plg.ctx, SCI_ADDREFDOCUMENT, 0, docs.doclist[docs.current].docptr)
  discard plg.ctx.msg(plg.ctx, SCI_SETDOCPOINTER, 0, docs.doclist[docid].docptr)
  discard plg.ctx.msg(plg.ctx, SCI_RELEASEDOCUMENT, 0, docs.doclist[docid].docptr)
  discard plg.ctx.msg(plg.ctx, SCI_GOTOPOS, docs.doclist[docid].cursor)

  docs.current = docid

  discard plg.ctx.handleCommand(plg.ctx, &"setTitle {docid}: {docs.doclist[docid].path}")

  discard plg.ctx.handleCommand(plg.ctx, "setLexer " & docs.doclist[docid].path)
  if plg.ctx.cmdParam.len != 0:
    discard plg.ctx.handleCommand(plg.ctx, "setTheme " & plg.ctx.cmdParam[0])

  if docs.doclist[docid].path != "Notifications":
    docs.doclist[docid].path.parentDir().setCurrentDir()
  else:
    getAppDir().setCurrentDir()

  discard plg.ctx.handleCommand(plg.ctx, "runHook postFileSwitch")

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
      buffer.setLen(bytesRead)
      discard plg.ctx.msg(plg.ctx, SCI_ADDTEXT, bytesRead, addr buffer[0])
      break
  f.close()

  discard plg.ctx.handleCommand(plg.ctx, "runHook postFileLoad")

proc open(plg: var Plugin) {.feudCallback.} =
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
    plg.ctx.cmdParam = @[]
    for d in dir.walkDirRec(yieldFilter={pcDir}):
      if ".git" notin d:
        if "*" in pat or "?" in pat or fileExists(d/pat):
          plg.ctx.cmdParam.add d/pat
    plg.open()

  proc openFuzzy(plg: var Plugin, path: string) =
    var
      (dir, pat) = path.getDirPat()
      bestscore = 0
      bestmatch = ""
      score: cint = 0
    plg.ctx.cmdParam = @[]
    for f in dir.walkDirRec():
      if ".git" notin f:
        if fuzzy_match(pat, f.extractFilename(), score):
          if score > bestscore:
            bestscore = score
            bestmatch = f
    if bestmatch.len != 0:
      discard plg.ctx.handleCommand(plg.ctx, &"togglePopup open {bestmatch}")

  for param in plg.getParam():
    let
      paths = param.split(" ")
      recurse = "-r" in paths
      fuzzy = "-f" in paths

    for path in paths:
      let
        path = path.strip()

      if "*" in path or "?" in path:
        if not recurse:
          plg.ctx.cmdParam = @[]
          for spath in path.walkPattern():
            plg.ctx.cmdParam.add spath.expandFilename()
          plg.open()
        else:
          plg.openRec(path)
      elif path notin ["-r", "-f", ""]:
        let
          docid = plg.findDocFromParam(path)
        if docid > -1:
          plg.switchDoc(docid)
        elif path.dirExists():
          plg.ctx.cmdParam = @[]
          for kind, file in path.walkDir():
            if kind == pcFile:
              plg.ctx.cmdParam.add file.expandFilename()
          plg.open()
        else:
          if not fileExists(path):
            if recurse:
              plg.openRec(path)
            elif fuzzy:
              plg.openFuzzy(path)
            else:
              plg.ctx.notify(plg.ctx, &"File does not exist: {path}")
          else:
            var
              path = path.expandFilename()
              docs = plg.getDocs()
              info = path.getFileInfo()
              doc = new(Doc)

            doc.path = path
            doc.docptr = plg.ctx.msg(plg.ctx, SCI_CREATEDOCUMENT, info.size.toPtr).toPtr

            docs.doclist.add doc

            plg.switchDoc(docs.doclist.len-1)

            plg.loadFileContents(path)

            discard plg.ctx.msg(plg.ctx, SCI_GOTOPOS, 0)

proc save(plg: var Plugin) {.feudCallback.} =
  var
    docs = plg.getDocs()

  if docs.doclist.len != 0 and docs.current != 0:
    discard plg.ctx.msg(plg.ctx, SCI_SETREADONLY, 1.toPtr)

    let
      doc = docs.doclist[docs.current]
      data = cast[cstring](plg.ctx.msg(plg.ctx, SCI_GETCHARACTERPOINTER))

    try:
      var
        f = open(doc.path, fmWrite)
      f.write(data)
      f.close()
      plg.ctx.notify(plg.ctx, &"Saved {doc.path}")
    except:
      plg.ctx.notify(plg.ctx, &"Failed to save {doc.path}")

    discard plg.ctx.msg(plg.ctx, SCI_SETREADONLY, 0.toPtr)

proc list(plg: var Plugin) {.feudCallback.} =
  var
    lout = ""
    docs = plg.getDocs()

  for i in 0 .. docs.doclist.len-1:
    lout &= &"{i}: {docs.doclist[i].path}\n"

  plg.ctx.notify(plg.ctx, lout[0..^2])

proc close(plg: var Plugin) {.feudCallback.} =
  var
    docs = plg.getDocs()
    param =
      if plg.ctx.cmdParam.len != 0:
        plg.ctx.cmdParam[0]
      else:
        ""

  var
    docid = plg.findDocFromParam(param)

  if docid > 0:
    if docid == docs.current:
      if docid == docs.doclist.len-1:
        plg.switchDoc(docid-1)
      else:
        plg.switchDoc(docid+1)
    else:
      if docid < docs.current:
        docs.current -= 1

    discard plg.ctx.msg(plg.ctx, SCI_RELEASEDOCUMENT, 0, docs.doclist[docid].docptr)
    docs.doclist.del(docid)

proc closeAll(plg: var Plugin) {.feudCallback.} =
  var
    docs = plg.getDocs()

  while docs.doclist.len != 1:
    plg.ctx.cmdParam = @[$(docs.doclist.len-1)]
    plg.close()

proc reload(plg: var Plugin) {.feudCallback.} =
  var
    docs = plg.getDocs()
    docid = docs.current

  if docid > 0:
    let
      path = docs.doclist[docid].path

    plg.loadFileContents(path)

    plg.ctx.notify(plg.ctx, &"Reloaded {path}")

proc next(plg: var Plugin) {.feudCallback.} =
  var
    docs = plg.getDocs()

  if docs.doclist.len != 1:
    var
      docid = docs.current
    docid += 1
    if docid == docs.doclist.len:
      docid = 0

    plg.switchDoc(docid)

proc prev(plg: var Plugin) {.feudCallback.} =
  var
    docs = plg.getDocs()

  if docs.doclist.len != 1:
    var
      docid = docs.current
    docid -= 1
    if docid < 0:
      docid = docs.doclist.len-1

    plg.switchDoc(docid)

feudPluginDepends(["filetype", "theme", "window"])

feudPluginLoad:
  var
    docs = plg.getDocs()

  if docs.doclist.len == 0:
    var
      notif = new(Doc)
    notif.path = "Notifications"
    notif.docptr = plg.ctx.msg(plg.ctx, SCI_GETDOCPOINTER).toPtr
    discard plg.ctx.msg(plg.ctx, SCI_SETDOCPOINTER, 0, notif.docptr, windowID=0)

    docs.doclist.add notif
    docs.current = 0

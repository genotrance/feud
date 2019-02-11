import os, segfaults, strformat, strutils, tables

import "../../src"/pluginapi

const MAX_BUFFER = 8192

type
  Doc = ref object
    path: string
    docptr: pointer

  Docs = ref object
    current: int
    doclist: seq[Doc]

proc getDocs(plg: var Plugin): Docs =
  return getCtxData[Docs](plg)

proc initDocs(plg: var Plugin) {.exportc, dynlib.} =
  var
    docs = plg.getDocs()

  if docs.doclist.len == 0:
    var
      notif = new(Doc)
    notif.path = "Notifications"
    notif.docptr = plg.ctx.eMsg(SCI_GETDOCPOINTER).toPtr

    docs.doclist.add notif
    docs.current = 0

proc findDocFromString(plg: var Plugin, srch: string): int =
  result = -1
  var
    docs = plg.getDocs()

  # Exact match
  for i in 0 .. docs.doclist.len-1:
    if srch == docs.doclist[i].path:
      result = i
      break

  # File name.ext match
  if result == -1:
    for i in 0 .. docs.doclist.len-1:
      if srch == docs.doclist[i].path.extractFilename():
        result = i
        break

  # File name match
  if result == -1:
    for i in 0 .. docs.doclist.len-1:
      if srch == docs.doclist[i].path.splitFile().name:
        result = i
        break

proc findDocFromParam(plg: var Plugin): int =
  var
    docs = plg.getDocs()
    param = plg.ctx.cmdParam[0]

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

  discard plg.ctx.eMsg(SCI_ADDREFDOCUMENT, 0, docs.doclist[docs.current].docptr)
  discard plg.ctx.eMsg(SCI_SETDOCPOINTER, 0, docs.doclist[docid].docptr)
  discard plg.ctx.eMsg(SCI_RELEASEDOCUMENT, 0, docs.doclist[docid].docptr)

  docs.current = docid

proc loadFileContents(plg: var Plugin, path: string) =
  if not fileExists(path):
    return

  discard plg.ctx.eMsg(SCI_CLEARALL)
  var
    buffer = newString(MAX_BUFFER)
    bytesRead = 0
    f = open(path)

  while true:
    bytesRead = readBuffer(f, addr buffer[0], MAX_BUFFER)
    if bytesRead == MAX_BUFFER:
      discard plg.ctx.eMsg(SCI_ADDTEXT, bytesRead, addr buffer[0])
    else:
      buffer.setLen(bytesRead)
      discard plg.ctx.eMsg(SCI_ADDTEXT, bytesRead, addr buffer[0])
      break
  f.close()

proc open(plg: var Plugin) {.feudCallback.} =
  let
    path = plg.ctx.cmdParam[0].deepCopy()

  if "*" in path or "?" in path:
    for file in path.walkPattern():
      plg.ctx.cmdParam = @[file]
      plg.open()
  else:
    let
      docid = plg.findDocFromParam()
    if docid > -1:
      plg.switchDoc(docid)
    elif path.dirExists():
      for kind, file in path.walkDir():
        if kind == pcFile:
          plg.ctx.cmdParam = @[file]
          plg.open()
    else:
      if not fileExists(path):
        plg.ctx.notify(plg.ctx, &"File does not exist: {path}")
      else:
        var
          docs = plg.getDocs()

        if plg.findDocFromString(path) < 0:
          var
            info = path.getFileInfo()
            doc = new(Doc)

          doc.path = path
          doc.docptr = plg.ctx.eMsg(SCI_CREATEDOCUMENT, info.size.toPtr).toPtr

          docs.doclist.add doc

        plg.switchDoc(docs.doclist.len-1)

        plg.loadFileContents(path)

proc list(plg: var Plugin) {.feudCallback.} =
  var
    lout = ""
    docs = plg.getDocs()

  for i in 0 .. docs.doclist.len-1:
    lout &= &"{i} {docs.doclist[i].path}\n"

  plg.ctx.notify(plg.ctx, lout[0..^2])

proc close(plg: var Plugin) {.feudCallback.} =
  var
    docs = plg.getDocs()

  var
    docid = plg.findDocFromParam()

  if docid > 0:
    if docid == docs.current:
      if docid == docs.doclist.len-1:
        plg.switchDoc(docid-1)
      else:
        plg.switchDoc(docid+1)
    else:
      if docid < docs.current:
        docs.current -= 1

    discard plg.ctx.eMsg(SCI_RELEASEDOCUMENT, 0, docs.doclist[docid].docptr)
    docs.doclist.del(docid)

feudPluginLoad:
  plg.initDocs()


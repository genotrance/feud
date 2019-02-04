import os, strformat, strutils, tables

import "../src"/pluginapi

const MAX_BUFFER = 8192

type
  Doc = ref object
    path: string
    docptr: pointer

  Docs = ref object
    current: int
    doclist: seq[Doc]

proc getDocs(ctx: var Ctx): Docs =
  if not ctx.pluginData.hasKey("file"):
    ctx.pluginData["file"] = cast[pointer](new(Docs))

  result = cast[Docs](ctx.pluginData["file"])

proc initDocs(ctx: var Ctx, plg: var Plugin) {.exportc, dynlib.} =
  var
    docs = ctx.getDocs()

  if docs.doclist.len == 0:
    var
      notif = new(Doc)
    notif.path = "Notifications"
    notif.docptr = ctx.eMsg(SCI_GETDOCPOINTER).toPtr

    docs.doclist.add notif
    docs.current = 0

proc findDocFromString(ctx: var Ctx, srch: string): int =
  result = -1
  var
    docs = ctx.getDocs()

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

proc findDocFromParam(ctx: var Ctx): int =
  var
    docs = ctx.getDocs()

  result =
    if ctx.cmdParam.len == 0:
      docs.current
    else:
      ctx.findDocFromString(ctx.cmdParam)

  if result < 0:
    try:
      result = parseInt(ctx.cmdParam)
    except ValueError:
      discard

proc switchDoc(ctx: var Ctx, docid: int) =
  var
    docs = ctx.getDocs()

  if docid < 0 or docid > docs.doclist.len-1 or docid == docs.current:
    return

  discard ctx.eMsg(SCI_ADDREFDOCUMENT, 0, docs.doclist[docs.current].docptr)
  discard ctx.eMsg(SCI_SETDOCPOINTER, 0, docs.doclist[docid].docptr)
  discard ctx.eMsg(SCI_RELEASEDOCUMENT, 0, docs.doclist[docid].docptr)

  docs.current = docid

proc loadFileContents(ctx: var Ctx, path: string) =
  if not fileExists(path):
    return

  discard ctx.eMsg(SCI_CLEARALL)
  var
    buffer = newString(MAX_BUFFER)
    bytesRead = 0
    f = open(path)

  while true:
    bytesRead = readBuffer(f, addr buffer[0], MAX_BUFFER)
    if bytesRead == MAX_BUFFER:
      discard ctx.eMsg(SCI_ADDTEXT, bytesRead, addr buffer[0])
    else:
      buffer.setLen(bytesRead)
      discard ctx.eMsg(SCI_ADDTEXT, bytesRead, addr buffer[0])
      break
  f.close()

proc open(ctx: var Ctx, plg: var Plugin) {.feudCallback.} =
  let
    path = ctx.cmdParam
    docid = ctx.findDocFromParam()

  if docid > -1:
    ctx.switchDoc(docid)
  else:
    if not fileExists(path):
      ctx.notify(&"File does not exist: {path}")
    else:
      var
        docs = ctx.getDocs()

      if ctx.findDocFromString(path) < 0:
        var
          info = path.getFileInfo()
          doc = new(Doc)

        doc.path = path
        doc.docptr = ctx.eMsg(SCI_CREATEDOCUMENT, info.size.toPtr).toPtr

        docs.doclist.add doc

      ctx.switchDoc(docs.doclist.len-1)

      ctx.loadFileContents(path)

proc list(ctx: var Ctx, plg: var Plugin) {.feudCallback.} =
  var
    lout = ""
    docs = ctx.getDocs()

  for i in 0 .. docs.doclist.len-1:
    lout &= &"{i} {docs.doclist[i].path}\n"

  ctx.notify(lout[0..^2])

proc close(ctx: var Ctx, plg: var Plugin) {.feudCallback.} =
  var
    docs = ctx.getDocs()

  var
    docid = ctx.findDocFromParam()

  if docid > 0:
    if docid == docs.current:
      if docid == docs.doclist.len-1:
        ctx.switchDoc(docid-1)
      else:
        ctx.switchDoc(docid+1)
    else:
      if docid < docs.current:
        docs.current -= 1

    discard ctx.eMsg(SCI_RELEASEDOCUMENT, 0, docs.doclist[docid].docptr)
    docs.doclist.del(docid)

feudPluginLoad:
  ctx.initDocs(plg)


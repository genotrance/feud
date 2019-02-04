import os, tables

import "../src"/pluginapi

const MAX_BUFFER = 8192

type
  File = ref object
    current: string
    documents: TableRef[string, pointer]

proc getFileData(ctx: var Ctx): File =
  if not ctx.pluginData.hasKey("file"):
    ctx.pluginData["file"] = cast[pointer](new(File))

  result = cast[File](ctx.pluginData["file"])

proc initDocuments(ctx: var Ctx, plg: var Plugin) {.exportc, dynlib.} =
  var
    fileData = ctx.getFileData()

  if fileData.documents.isNil:
    fileData.documents = newTable[string, pointer]()

    fileData.documents["UNTITLED"] = ctx.eMsg(SCI_GETDOCPOINTER).toPtr
    fileData.current = "UNTITLED"

proc switchFile(name: string, ctx: var Ctx) =
  var
    fileData = ctx.getFileData()

  if fileData.current == name or not fileData.documents.hasKey(name):
    return

  discard ctx.eMsg(SCI_ADDREFDOCUMENT, 0, fileData.documents[fileData.current])
  discard ctx.eMsg(SCI_SETDOCPOINTER, 0, fileData.documents[name])
  discard ctx.eMsg(SCI_RELEASEDOCUMENT, 0, fileData.documents[name])

  fileData.current = name

proc loadFileContents(name: string, ctx: var Ctx) =
  if not fileExists(name):
    return

  discard ctx.eMsg(SCI_CLEARALL)
  var
    buffer = newString(MAX_BUFFER)
    bytesRead = 0
    f = open(name)

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
    name = ctx.cmdParam

  if not fileExists(name):
    ctx.notify("File does not exist")
  else:
    var
      fileData = ctx.getFileData()

    if not fileData.documents.hasKey(name):
      var
        info = name.getFileInfo()
        doc = ctx.eMsg(SCI_CREATEDOCUMENT, info.size.toPtr).toPtr

      fileData.documents[name] = doc

    switchFile(name, ctx)

    loadFileContents(name, ctx)

proc list(ctx: var Ctx, plg: var Plugin) {.feudCallback.} =
  var
    lout = ""
    fileData = ctx.getFileData()

  for name in fileData.documents.keys():
    lout &= name & "\n"

  ctx.notify(lout)

feudPluginLoad:
  discard
  # ctx.initDocuments(plg)


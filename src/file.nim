import os, tables

when defined(Windows):
  import "."/win

import "."/[globals, scihelper, scintilla]

const MAX_BUFFER = 8192

var
  current*: string
  documents*: TableRef[string, pointer]

    of "open", "o":
      if param.len != 0:
        param.openFile()
    of "list", "l":
      listFiles()

proc initDocuments*() =
  if gSciState.documents.isNil:
    gSciState.documents = newTable[string, pointer]()

    gSciState.documents["UNTITLED"] = SCI_GETDOCPOINTER.eMsg().toPtr
    gSciState.current = "UNTITLED"

proc switchFile*(name: string) =
  if gSciState.current == name or not gSciState.documents.hasKey(name):
    return

  SCI_ADDREFDOCUMENT.eMsg(0, gSciState.documents[gSciState.current])
  SCI_SETDOCPOINTER.eMsg(0, gSciState.documents[name])
  SCI_RELEASEDOCUMENT.eMsg(0, gSciState.documents[name])

  gSciState.current = name

proc loadFileContents*(name: string) =
  if not fileExists(name):
    return

  SCI_CLEARALL.eMsg()
  var
    buffer = newString(MAX_BUFFER)
    bytesRead = 0
    f = open(name)

  while true:
    bytesRead = readBuffer(f, addr buffer[0], MAX_BUFFER)
    if bytesRead == MAX_BUFFER:
      SCI_ADDTEXT.eMsg(bytesRead, addr buffer[0])
    else:
      buffer.setLen(bytesRead)
      SCI_ADDTEXT.eMsg(bytesRead, addr buffer[0])
      break
  f.close()

proc openFile*(name: string) =
  if not fileExists(name):
    notify("File does not exist")
    return

  if not gSciState.documents.hasKey(name):
    var
      info = name.getFileInfo()
      doc = SCI_CREATEDOCUMENT.eMsg(info.size.toPtr).toPtr

    gSciState.documents[name] = doc

  switchFile(name)

  loadFileContents(name)

proc listFiles*() =
  var
    lout = ""

  for name in gSciState.documents.keys():
    lout &= name & "\n"

  lout.notify()
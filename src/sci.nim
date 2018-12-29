import tables

import nimscintilla/[Scintilla, SciLexer]

when defined(Windows):
  import "."/win

import "."/[actions, globals]

proc initScintilla() =
  if Scintilla_RegisterClasses(nil) == 0:
    raise newException(Exception, "Failed to initialize Scintilla")

  discard Scintilla_LinkLexers()

proc exitScintilla() =
  if Scintilla_ReleaseResources() == 0:
    raise newException(Exception, "Failed to exit Scintilla")

proc commandCallback() =
  let
    pos = SCI_GETCURRENTPOS.cMsg()
    line = SCI_LINEFROMPOSITION.cMsg(pos)
    length = SCI_LINELENGTH.cMsg(line)

  if length != 0:
    var
      data = alloc0(length+1)
    defer: data.dealloc()

    if SCI_GETLINE.cMsg(line, data) == length:
      ($cast[cstring](data)).handleCommand()

proc feudStart*() =
  initScintilla()

  createWindows()
  initDocuments()
  commandCallback.messageLoop()

  exitScintilla()

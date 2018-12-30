import strutils, tables

import nimscintilla/[Scintilla, SciLexer, Scitable]

when defined(Windows):
  import "."/win

import "."/[file, globals, scihelper]

proc initDocuments*() =
  if gSciState.documents.isNil:
    gSciState.documents = newTable[string, pointer]()

    gSciState.documents["UNTITLED"] = SCI_GETDOCPOINTER.eMsg().toPtr
    gSciState.current = "UNTITLED"

proc toInt(sval: string, ival: var int): bool =
  let
    parseProc = if "0x" in sval: parseHexInt else: parseInt

  try:
    ival = sval.parseProc()
    result = true
  except:
    discard

proc execMsg(cmd, param: string) =
  let
    spl = param.split(" ", maxsplit=3)
    msgProc = if cmd == "emsg": eMsg else: cMsg

  var
    s, l, w: int
    wc: cstring

  if not spl[0].toInt(s):
    notify("Bad integer value " & spl[0])
    return

  if spl.len > 1:
    if not spl[1].toInt(l):
      notify("Bad integer value " & spl[1])
      return

    if spl.len > 2:
      if not spl[2].toInt(w):
        wc = spl[2].cstring
        msgProc(s, l, wc).notify()
      else:
        msgProc(s, l, w).notify()
    else:
      msgProc(s, l).notify()
  else:
    msgProc(s).notify()

proc handleCommand*(command: string) =
  let
    spl = command.strip().split(" ", maxsplit=1)

  var
    cmd = spl[0]
    param = ""
  if spl.len == 2:
    param = spl[1]

  case cmd:
    of "open", "o":
      if param.len != 0:
        param.openFile()
    of "list", "l":
      listFiles()
    of "emsg", "cmsg":
      if param.len != 0:
        execMsg(cmd, param)
    of "quit":
      exitWindow()
    else:
      echo cmd

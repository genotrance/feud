import nimscintilla/[Scintilla, SciLexer]

when defined(Windows):
  import "."/win

import "."/globals

proc notify*(msg: string|int) =
  let
    msgn = "\n" & $msg
  SCI_ADDTEXT.cMsg(msgn.len, msgn.cstring)

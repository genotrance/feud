import ospaths, strutils

let
  feudRun = "cmd /c start feud"
  feudCRun = "cmd /c feudc"

proc execFeudC(cmds: seq[string]) =
  var
    fCmd = feudCRun

  for cmd in cmds:
    fCmd &= " " & cmd.strip().quoteShell

  exec fCmd

exec feudRun
exec "sleep 2"

include "."/comment

execFeudC(@["script tests/crash1.ini"])
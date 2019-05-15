import ospaths, strutils

let
  feudRun = "cmd /c start feud"
  feudCRun = "cmd /c feudc"

proc execFeudC(cmds: seq[string]): string =
  var
    fCmd = feudCRun
    exitCode = 0

  for cmd in cmds:
    fCmd &= " " & cmd.strip().quoteShell

  echo fCmd
  (result, exitCode) = gorgeEx(fCmd)
  echo result
  if exitCode != 0:
    quit(1)

proc execFeudC(cmd: string): string =
  return execFeudC(@[cmd])

proc sleep(t: float) =
  exec "sleep " & $t

exec feudRun
sleep(2)

include "."/comment
include "."/file

doAssert execFeudC("script tests/crash1.ini").contains("globals.nim"), "Failed crash1 test"

discard execFeudC("quit")
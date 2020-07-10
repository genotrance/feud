# Package

version     = "0.1.0"
author      = "genotrance"
description = "Fed Ep with UDitors"
license     = "MIT"

# Dependencies

requires "nim >= 0.19.0", "c2nim >= 0.9.14", "nimterop >= 0.6.2"
requires "cligen >= 1.0.0", "winim >= 3.3.5", "xml >= 0.1.3"

when defined(Windows):
  requires "cmake >= 0.1.0"

import strutils

var
  dll = ".dll"
  exe = ".exe"
  flags = "-d:release"

when defined(Linux):
  dll = ".so"
  exe = ""
elif defined(OSX):
  dll = ".dylib"
  exe = ""

task cleandll, "Clean DLLs":
  for dir in @["plugins", "plugins/client", "plugins/server"]:
    for file in dir.listFiles():
      if dll in file:
        rmFile file

task clean, "Clean all":
  var exe = when defined(Windows): ".exe" else: ""

  rmFile "feud" & exe
  rmFile "feudc" & exe
  rmFile "wrappers/scintillawrapper.nim"
  rmFile "wrappers/libscilexer.a"
  cleandllTask()

proc echoExec(cmd: string) =
  echo cmd
  exec cmd

proc stripDlls(path: string) =
  for file in listFiles(path):
    if dll in file:
      exec "strip -s " & file

proc buildDlls(path: string) =
  for file in listFiles(path):
    if file[^4 .. ^1] == ".nim":
      echo "Building " & file
      echoExec "nim c --app:lib " & flags & " " & file

proc execDlls(task: proc(path: string)) =
  for dir in ["plugins", "plugins/server", "plugins/client"]:
    task(dir)

task dll, "Build dlls":
  execDlls(buildDlls)
  if "-g" notin flags:
    execDlls(stripDlls)

task feud, "Build feud":
  echoExec "nim c " & flags & " feud"
  if "-g" notin flags:
    echoExec "strip -s feud" & exe

task feudc, "Build feud":
  echoExec "nim c " & flags & " feudc"
  if "-g" notin flags:
    echoExec "strip -s feudc" & exe

task release, "Release build":
  feudTask()
  feudcTask()
  dllTask()

task binary, "Release binary":
  flags = "-d:binary " & flags
  releaseTask()

task debug, "Debug build":
  flags = "-g"
  releaseTask()

task ddll, "Debug binaries":
  flags = "-g"
  dllTask()

task dfeud, "Debug binaries":
  flags = "-g"
  feudTask()

task dfeudc, "Debug binaries":
  flags = "-g"
  feudcTask()

task test, "Tester":
  echoExec "nim tests/test.nims"
# Package

version     = "0.1.0"
author      = "genotrance"
description = "Fed Ep with UDitors"
license     = "MIT"

# Dependencies

requires "nim >= 0.19.0", "nimterop >= 0.1.0", "winim >= 2.5.2", "cligen >= 0.9.17", "nimdeps >= 0.1.0"

import strutils

var
  dll = ".dll"
  exe = ".exe"

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
  var
    exe =
      when defined(Windows):
        ".exe"
      else:
        ""

  rmFile "feud" & exe
  rmFile "feudc" & exe
  cleandllTask()

proc stripDlls(path: string) =
  for file in listFiles(path):
    if dll in file:
      exec "strip -s " & file

proc buildDlls(path: string) =
  for file in listFiles(path):
    if file[^4 .. ^1] == ".nim":
      echo "Building " & file
      exec "nim c --app:lib -d:release " & file
  stripDlls(path)

proc execDlls(task: proc(path: string)) =
  for dir in ["plugins", "plugins/server", "plugins/client"]:
    task(dir)

task dll, "Build dlls":
  execDlls(buildDlls)
  execDlls(stripDlls)

task release, "Release build":
  dllTask()
  exec "nim c -d:release feudc"
  exec "nim c -d:release feud"
  exec "strip -s feudc" & exe
  exec "strip -s feud" & exe

task binary, "Release binary":
  dllTask()
  exec "nim c -d:release feudc"
  exec "nim c -d:binary -d:release feud"
  exec "strip -s feudc" & exe
  exec "strip -s feud" & exe

task debug, "Debug build":
  exec "nim c --debugger:native feud"


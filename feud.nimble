# Package

version     = "0.1.0"
author      = "genotrance"
description = "Fed Ep with UDitors"
license     = "MIT"

bin = @["feud", "feudc"]

# Dependencies

requires "nim >= 0.19.0", "nimterop >= 0.1.0", "winim >= 2.5.2", "cligen >= 0.9.17", "nimdeps >= 0.1.0"

import os, strutils

task cleandll, "Clean DLLs":
  var
    dll = ".dll"

  when defined(Linux):
    dll = ".so"
  elif defined(OSX):
    dll = ".dylib"

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

proc buildDlls(path: string) =
  for dll in listFiles(path):
    if dll.splitFile.ext == ".nim":
      exec "nim c --app:lib -d:release --opt:speed " & dll

task dll, "Build dlls":
  buildDlls("plugins")
  buildDlls("plugins/server")
  buildDlls("plugins/client")

task release, "Release build":
  dllTask()
  exec "nim c -d:release --opt:speed feudc"
  exec "nim c -d:release --opt:speed feud"

task binary, "Release binary":
  dllTask()
  exec "nim c -d:release --opt:speed feudc"
  exec "nim c -d:binary -d:release --opt:speed feud"

task debug, "Debug build":
  exec "nim c --debugger:native feud"


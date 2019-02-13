import os, strutils, tables

import nimterop/[cimport, git]

const
  sciDir = currentSourcePath().parentDir().parentDir()/"build"/"scintilla"

static:
  #cDebug()
  gitPull("https://github.com/mirror/scintilla", sciDir)

cIncludeDir(sciDir/"include")
cIncludeDir(sciDir/"src")
cIncludeDir(sciDir/"lexlib")

when defined(Windows):
  cCompile(sciDir/"win32/*.cxx")

  {.passC: "-UWIN32_LEAN_AND_MEAN".}
  {.passL: "-lgdi32 -luser32 -limm32 -lole32 -luuid -loleaut32 -lmsimg32 -lstdc++".}

when defined(Linux):
  cCompile(sciDir/"gtk/*.cxx")

  {.passC: \"-DGTK".}

cCompile(sciDir/"src/*.cxx")
cCompile(sciDir/"lexlib/*.cxx")
cCompile(sciDir/"lexers/*.cxx")

{.passC: "--std=c++17 -DNDEBUG -DSCI_LEXER".}

cImport(sciDir/"include/Scintilla.h", recurse=true)
cImport(sciDir/"include/SciLexer.h")

const SciDefs* = (block:
  var
    scvr = initTable[string, int]()
    path = currentSourcePath.parentDir().parentDir()/"build"/"scintilla"/"include"

  for file in ["Scintilla.h", "SciLexer.h"]:
    for line in staticRead(path/file).splitLines():
      if "#define" in line:
        var
          spl = line.split(' ')
        if spl.len == 3 and spl[1][0] == 'S':
          let
            parseProc = if "0x" in spl[2]: parseHexInt else: parseInt
          scvr[spl[1]] = spl[2].parseProc()

  scvr
)

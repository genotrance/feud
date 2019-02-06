import os

import nimterop/[cimport, git]

const
  baseDir = currentSourcePath().parentDir().parentDir()/"build"
  sciDir = baseDir/"scintilla"

static:
  #cDebug()
  downloadUrl("https://www.scintilla.org/scintilla412.zip", baseDir)

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

{.passC: "--std=c++17 -DNDEBUG".}

cImport(sciDir/"include/Scintilla.h", recurse=true)
cImport(sciDir/"include/SciLexer.h")
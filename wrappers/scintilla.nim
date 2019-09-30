import os

import nimterop/[cimport, git]

const
  sciDir = currentSourcePath().parentDir().parentDir()/"build"/"scintilla"

static:
  gitPull("https://github.com/mirror/scintilla", sciDir)

cIncludeDir(sciDir/"include")
cIncludeDir(sciDir/"src")
cIncludeDir(sciDir/"lexlib")

when defined(Windows):
  cCompile(sciDir/"win32/*.cxx")

  {.passC: "-UWIN32_LEAN_AND_MEAN".}
  {.passL: "-static -lgdi32 -luser32 -limm32 -lole32 -luuid -loleaut32 -lmsimg32 -lstdc++".}

when defined(Linux):
  cCompile(sciDir/"gtk/*.cxx")
  cCompile(sciDir/"gtk/*.c")

  {.passC: "-DGTK " & gorge("pkg-config --cflags gtk+-2.0").}
  {.passL: "-lgmodule-2.0 " & gorge("pkg-config --libs gtk+-2.0").}

cCompile(sciDir/"src/*.cxx")
cCompile(sciDir/"lexlib/*.cxx")
cCompile(sciDir/"lexers/*.cxx")

{.passC: "--std=c++17 -DNDEBUG -DSCI_LEXER".}

cImport(sciDir/"include/Scintilla.h", recurse=true)
cImport(sciDir/"include/SciLexer.h")

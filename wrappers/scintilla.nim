import os

import nimterop/[cimport, build]

const
  baseDir = getProjectCacheDir("feud" / "scintilla")
  sciDir = baseDir / "scintilla"

static:
  downloadUrl("https://www.scintilla.org/scintilla443.zip", baseDir)

cIncludeDir(sciDir/"include")

when defined(Windows):
  static:
    make(sciDir / "win32", "ScintillaWin.o")

  {.passL: sciDir / "bin" / "libscintilla.a" &
    " -static -lgdi32 -luser32 -limm32 -lole32 -luuid -loleaut32 -lmsimg32 -lstdc++".}

when defined(Linux):
  static:
    make(sciDir / "gtk", "ScintillaGTK.o")

  {.passL: sciDir / "bin" / "libscintilla.a" &
    " -lgmodule-2.0 " & gorge("pkg-config --libs gtk+-2.0").}

cImport(@[sciDir/"include/Scintilla.h", sciDir/"include/SciLexer.h"],
  recurse = true, nimFile = sciDir / "scintilla.nim")

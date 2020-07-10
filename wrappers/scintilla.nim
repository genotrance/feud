import os

import nimterop/[cimport, build]

const
  baseDir = getProjectCacheDir("feud" / "scintilla")
  sciDir = baseDir / "scintilla"
  wDir = currentSourcePath().parentDir()

static:
  downloadUrl("https://www.scintilla.org/scintilla443.zip", baseDir)

cIncludeDir(sciDir/"include")

when isMainModule:
  # Compile into libscilexer.lib
  cIncludeDir(sciDir/"src")
  cIncludeDir(sciDir/"lexlib")

  when defined(Windows):
    cCompile(sciDir/"win32/*.cxx")

    {.passC: "-UWIN32_LEAN_AND_MEAN".}

  elif defined(Linux):
    cCompile(sciDir/"gtk/*.cxx")
    cCompile(sciDir/"gtk/*.c")

    {.passC: "-DGTK " & gorge("pkg-config --cflags gtk+-2.0").}

  cCompile(sciDir/"src/*.cxx")
  cCompile(sciDir/"lexlib/*.cxx")
  cCompile(sciDir/"lexers/*.cxx")

  {.passC: "--std=c++17 -DNDEBUG -DSCI_LEXER".}
else:
  when not fileExists(wDir / "libscilexer.a"):
    static:
      echo "Building libscilexer.a"
      let
        (outp, err) = gorgeEx("nim c -d:danger --app:staticlib -o:libscilexer.a scintilla.nim")
      doAssert err == 0, "\n\nFailed to compile libscilexer.a\n\n" & outp

  {.passL: wDir / "libscilexer.a".}
  when defined(Windows):
    {.passL: "-static -lgdi32 -luser32 -limm32 -lole32 -luuid -loleaut32 -lmsimg32 -lstdc++".}

  elif defined(Linux):
    {.passL: "-lgmodule-2.0 " & gorge("pkg-config --libs gtk+-2.0").}

  cImport(
    @[sciDir/"include/Scintilla.h", sciDir/"include/SciLexer.h"],
    recurse = true, nimFile = currentSourcePath.parentDir() / "scintillawrapper.nim"
  )

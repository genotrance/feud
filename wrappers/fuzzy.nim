import os

import nimterop/[cimport, build]

const
  fuzDir = getProjectCacheDir("feud"/"fuzzy")
  fuzFile = fuzDir/"fts_fuzzy_match.h"

static:
  if not fileExists(fuzFile):
    downloadUrl("https://github.com/forrestthewoods/lib_fts/raw/master/code/fts_fuzzy_match.h", fuzDir)

{.passC: "--std=c++11 -DFTS_FUZZY_MATCH_IMPLEMENTATION".}

type
  uint8_t = uint8

c2nimport(fuzFile, mode = "cpp", flags = "--cpp")

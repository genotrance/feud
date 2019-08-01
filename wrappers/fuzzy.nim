import os

import nimterop/[cimport, git]

const
  fuzDir = currentSourcePath().parentDir().parentDir()/"build"/"fuzzy"
  fuzFile = fuzDir/"fts_fuzzy_match.h"

static:
  cDebug()
  if not fileExists(fuzFile):
    downloadUrl("https://github.com/forrestthewoods/lib_fts/raw/master/code/fts_fuzzy_match.h", fuzDir)

{.passC: "--std=c++11 -DFTS_FUZZY_MATCH_IMPLEMENTATION".}

c2nimport(fuzFile, flags = "--cpp")

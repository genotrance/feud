import os, strutils, tables

import nimterop/[cimport, git]

const
  fuzDir = currentSourcePath().parentDir().parentDir()/"build"/"fuzzy"
  fuzFile = fuzDir/"fts_fuzzy_match.h"

static:
  if not fileExists(fuzFile):
    downloadUrl("https://github.com/forrestthewoods/lib_fts/raw/master/code/fts_fuzzy_match.h", fuzDir)

{.passC: "--std=c++11 -DFTS_FUZZY_MATCH_IMPLEMENTATION".}

proc fuzzy_match*(pattern, str: cstring, outScore: var int): bool {.importcpp: "fts::fuzzy_match(@)", header: fuzFile.}

import macros, os, sets, strformat, strutils, tables

import nimterop/cimport

import "."/globals
export Plugin, Ctx, toPtr

# Scintilla constants
const
  baseDir = currentSourcePath().parentDir().parentDir()/"build"
  sciDir = baseDir/"scintilla"

cIncludeDir(sciDir/"include")
cImport(sciDir/"include/Scintilla.h", recurse=true)
cImport(sciDir/"include/SciLexer.h")

# Find callbacks
var
  ctcallbacks {.compiletime.}: HashSet[string]

static:
  ctcallbacks.init()

macro feudCallback*(body): untyped =
  if body.kind == nnkProcDef:
    ctcallbacks.incl $body[0]

    body.addPragma(ident("exportc"))
    body.addPragma(ident("dynlib"))

  result = body

  echo result.treeRepr

const
  callbacks = ctcallbacks

macro feudPluginLoad*(body: untyped): untyped =
  result = quote do:
    proc onLoad*(ctx: var Ctx, plg: var Plugin) {.exportc, dynlib.} =
      plg.cindex = callbacks

      `body`

macro feudPluginUnload*(body: untyped): untyped =
  result = quote do:
    proc onUnload*(ctx: var Ctx, plg: var Plugin) {.exportc, dynlib.} =
      `body`
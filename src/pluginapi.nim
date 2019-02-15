import macros, os, sets, strformat, strutils, tables

import nimterop/cimport

import "."/[globals, utils]
export Plugin, Ctx
export utils

# Scintilla constants
const
  baseDir = currentSourcePath().parentDir().parentDir()/"build"
  sciDir = baseDir/"scintilla"

cIncludeDir(sciDir/"include")
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

const
  callbacks = ctcallbacks

template feudPluginLoad*(body: untyped) {.dirty.} =
  proc onLoad*(plg: var Plugin) {.exportc, dynlib.} =
    bind callbacks
    plg.cindex = callbacks

    body

template feudPluginLoad*() {.dirty.} =
  feudPluginLoad:
    discard

template feudPluginUnload*(body: untyped) {.dirty.} =
  proc onUnload*(plg: var Plugin) {.exportc, dynlib.} =
    body

template feudPluginTick*(body: untyped) {.dirty.} =
  proc onTick*(plg: var Plugin) {.exportc, dynlib.} =
    body

template feudPluginNotify*(body: untyped) {.dirty.} =
  proc onNotify*(plg: var Plugin) {.exportc, dynlib.} =
    body

template feudPluginDepends*(deps) =
  proc onDepends*(plg: var Plugin) {.exportc, dynlib.} =
    plg.depends.add deps

proc getCtxData*[T](plg: var Plugin): T =
  if not plg.ctx.pluginData.hasKey(plg.name):
    var
      data = new(T)
    GC_ref(data)
    plg.ctx.pluginData[plg.name] = cast[pointer](data)

  result = cast[T](plg.ctx.pluginData[plg.name])

proc freeCtxData*[T](plg: var Plugin) =
  if plg.ctx.pluginData.hasKey(plg.name):
    var
      data = cast[T](plg.ctx.pluginData[plg.name])
    GC_unref(data)

    plg.ctx.pluginData.del(plg.name)

proc getPlgData*[T](plg: var Plugin): T =
  if plg.pluginData.isNil:
    var
      data = new(T)
    GC_ref(data)
    plg.pluginData = cast[pointer](data)

  result = cast[T](plg.pluginData)

proc freePlgData*[T](plg: var Plugin) =
  if not plg.pluginData.isNil:
    var
      data = cast[T](plg.pluginData)
    GC_unref(data)

    plg.pluginData = nil
import macros, os, sets, strformat, strutils, tables

import nimterop/[cimport, git]

import "."/[globals, utils]
export Plugin, Ctx
export utils

# Scintilla constants
const
  sciDir = currentSourcePath().parentDir().parentDir()/"build"/"scintilla"

static:
  gitPull("https://github.com/mirror/scintilla", sciDir)

cIncludeDir(sciDir/"include")
cImport(sciDir/"include/Scintilla.h", recurse=true)
cImport(sciDir/"include/SciLexer.h")

const SciDefs* = (block:
  var
    scvr = initTable[string, int]()
    path = sciDir/"include"

  for file in ["Scintilla.h", "SciLexer.h"]:
    for line in staticRead(path/file).splitLines():
      if "#define" in line:
        var
          spl = line.split(' ')
        if spl.len == 3 and spl[1][0] in ['S', 'I']:
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

proc getSelection*(plg: var Plugin): string =
  let
    length = plg.ctx.msg(plg.ctx, SCI_GETSELTEXT, 0, nil)
  if length != 0:
    var
      data = alloc0(length+1)
    defer: data.dealloc()

    discard plg.ctx.msg(plg.ctx, SCI_GETSELTEXT, 0, data)
    result = ($cast[cstring](data)).strip()

proc gotoEnd*(plg: var Plugin) =
  let
    length = plg.ctx.msg(plg.ctx, SCI_GETLENGTH)
  discard plg.ctx.msg(plg.ctx, SCI_GOTOPOS, length)

proc getCbResult*(plg: var Plugin, command: string): string =
  if plg.ctx.handleCommand(plg.ctx, command):
    if plg.ctx.cmdParam.len != 0 and plg.ctx.cmdParam[0].len != 0:
      return plg.ctx.cmdParam[0]

proc getCbIntResult*(plg: var Plugin, command: string, default = 0): int =
  let
    str = plg.getCbResult(command)

  try:
    result = parseInt(str)
  except:
    result = default
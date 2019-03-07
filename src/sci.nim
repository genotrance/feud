import os, strutils, tables

import "."/[globals, plugin, utils]

import ".."/wrappers/scintilla

proc initScintilla() =
  if Scintilla_RegisterClasses(nil) == 0:
    raise newException(Exception, "Failed to initialize Scintilla")

  discard Scintilla_LinkLexers()

proc exitScintilla() =
  if Scintilla_ReleaseResources() == 0:
    raise newException(Exception, "Failed to exit Scintilla")

proc handleCommand*(ctx: var Ctx, command: string): bool =
  result = true
  let
    spl = command.strip().split(" ", maxsplit=1)
    cmd = spl[0]

  var param = if spl.len == 2: spl[1] else: ""

  case cmd:
    of "quit", "exit":
      ctx.run = false
    else:
      if param.len != 0:
        ctx.cmdParam = @[param]
      else:
        ctx.cmdParam = @[]
      result = ctx.handlePluginCommand(cmd)

proc initCtx(): Ctx =
  result = new(Ctx)

  result.run = true
  result.handleCommand = handleCommand

proc feudStart*() =
  var
    ctx = initCtx()

  initScintilla()
  ctx.initPlugins("server")

  while ctx.run:
    ctx.syncPlugins()
    sleep(10)

  ctx.stopPlugins()
  exitScintilla()

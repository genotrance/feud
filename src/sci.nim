import strutils

import "."/[globals, plugin, utils]

import ".."/wrappers/scintilla

proc initScintilla() =
  when defined(windows):
    if Scintilla_RegisterClasses(nil) == 0:
      raise newException(Exception, "Failed to initialize Scintilla")

  discard Scintilla_LinkLexers()

proc exitScintilla() =
  when defined(windows):
    if Scintilla_ReleaseResources() == 0:
      raise newException(Exception, "Failed to exit Scintilla")

proc handleCommand*(ctx: Ctx, cmd: CmdData) =
  if cmd.params.len != 0:
    case cmd.params[0]:
      of "quit", "exit":
        ctx.run = stopped
      of "notify":
        if cmd.params.len > 1:
          ctx.notify(ctx, cmd.params[1 .. ^1].join(" "))
        else:
          cmd.failed = true
      else:
        ctx.handlePluginCommand(cmd)
  else:
    cmd.failed = true

proc initCtx(): Ctx =
  result = new(Ctx)

  result.run = executing
  result.handleCommand = handleCommand

proc feudStart*(cmds: seq[string]) =
  var
    ctx = initCtx()

  ctx.cli = cmds

  initScintilla()
  ctx.initPlugins(server)

  while ctx.run == executing:
    ctx.syncPlugins()

  ctx.stopPlugins()
  exitScintilla()

import tables

when defined(Windows):
  import "."/win

import "."/[actions, globals, plugin]

import ".."/wrappers/scintilla

proc initScintilla() =
  if Scintilla_RegisterClasses(nil) == 0:
    raise newException(Exception, "Failed to initialize Scintilla")

  discard Scintilla_LinkLexers()

proc exitScintilla() =
  if Scintilla_ReleaseResources() == 0:
    raise newException(Exception, "Failed to exit Scintilla")

proc commandCallback(ctx: var Ctx) =
  let
    pos = SCI_GETCURRENTPOS.cMsg()
    line = SCI_LINEFROMPOSITION.cMsg(pos)
    length = SCI_LINELENGTH.cMsg(line)

  if length != 0:
    var
      data = alloc0(length+1)
    defer: data.dealloc()

    if SCI_GETLINE.cMsg(line, data) == length:
      handleCommand(ctx, $cast[cstring](data))

proc notify(msg: string) =
  let
    msgn = "\n" & msg
  SCI_APPENDTEXT.cMsg(msgn.len, msgn.cstring)
  SCI_GOTOPOS.cMsg(SCI_GETLENGTH.cMsg())

proc initCtx(): Ctx =
  result = new(Ctx)

  result.eMsg = eMsg
  result.cMsg = cMsg
  result.notify = notify
  result.handleCommand = handleCommand

  result.plugins = newTable[string, Plugin]()
  result.pluginData = newTable[string, pointer]()

proc feudStart*() =
  var
    ctx = initCtx()

  initScintilla()

  ctx.createWindows()
  ctx.initPlugins()
  ctx.messageLoop(commandCallback, syncPlugins)

  ctx.stopPlugins()
  exitScintilla()

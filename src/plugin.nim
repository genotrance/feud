import dynlib, os, osproc, sequtils, sets, strformat, strutils, tables, threadpool, times

import "."/[globals]

var
  gMch: ptr Channel[string]

proc newPtrChannel[T](): ptr Channel[T] =
  result = cast[ptr Channel[T]](allocShared0(sizeof(Channel[T])))
  result[].open()

proc close[T](sch: var ptr Channel[T]) =
  sch[].close()
  sch.deallocShared()
  sch = nil

proc dll(sourcePath: string): string =
  let
    (dir, name, _) = sourcePath.splitFile()

  result = dir / (DynlibFormat % name)

proc needsRebuild(sourcePath, dllPath: string): bool =
  if not dllPath.fileExists() or
    sourcePath.getLastModificationTime() > dllPath.getLastModificationTime():
    result = true

proc monitorPlugins(ch: ptr Channel[string]) {.thread.} =
  var
    run = true
    loaded: HashSet[string]

  loaded.init()
  while run:
    let
      (ready, command) = ch[].tryRecv()

    if ready and command == "exit":
      run = false
    else:
      for sourcePath in walkFiles("plugins/*.nim"):
        let
          dllPath = sourcePath.dll
        if sourcePath.needsRebuild(dllPath):
          let
            relbuild =
              when defined(release):
                "-d:release"
              else:
                ""
            (output, exitCode) = execCmdEx(&"nim c --app:lib -o:{dllPath}.new {relbuild} {sourcePath}")
          if exitCode != 0:
            doAssert ch[].trySend(&"{output}\nPlugin compilation failed for {sourcePath}"), "trySend() failure: plugin rebuild failure"
          else:
            if sourcePath notin loaded:
              loaded.incl sourcePath
            doAssert ch[].trySend(&"{dllPath}.new"), "trySend() failure: plugin rebuild"
        elif sourcePath notin loaded:
          loaded.incl sourcePath
          doAssert ch[].trySend(&"{dllPath}"), "trySend() failure: plugin load"

      sleep(5000)

proc initPlugins*(ctx: var Ctx) =
  ctx.plugins = newTable[string, Plugin]()

  gMch = newPtrChannel[string]()
  spawn monitorPlugins(gMch)

proc unloadPlugin(ctx: var Ctx, name: string) =
  if ctx.plugins.hasKey(name):
    if not ctx.plugins[name].onUnload.isNil:
      ctx.plugins[name].onUnload(ctx.plugins[name])

    ctx.plugins[name].handle.unloadLib()
    ctx.plugins.del(name)

    ctx.notify(&"Unloaded {name}")

proc loadPlugin(ctx: var Ctx, dllPath: string) =
  var
    plg = new(Plugin)

  plg.ctx = ctx
  plg.path =
    if dllPath.splitFile().ext == ".new":
      dllPath[0 .. ^5]
    else:
      dllPath

  plg.name = plg.path.splitFile().name
  ctx.unloadPlugin(plg.name)

  if dllPath.splitFile().ext == ".new":
    var
      count = 10
    while count != 0 and tryRemoveFile(plg.path) == false:
      sleep(250)
      count -= 1

    if fileExists(plg.path):
      ctx.notify("Failed to unload {plg.name}")
      return

    moveFile(dllPath, plg.path)

  plg.handle = plg.path.loadLib()
  plg.cindex.init()
  plg.callbacks = newTable[string, PCallback]()
  if plg.handle.isNil:
    ctx.notify(&"Plugin {plg.name} failed to load")
  else:
    let
      onLoad = cast[PCallback](plg.handle.symAddr("onLoad"))
    if onLoad.isNil:
      ctx.notify(&"Plugin {plg.name} does not call 'feudPluginLoad()'")
    else:
      plg.onLoad()
      plg.onUnload = cast[PCallback](plg.handle.symAddr("onUnload"))
      for cb in plg.cindex:
        plg.callbacks[cb] = cast[PCallback](plg.handle.symAddr(cb))
        if plg.callbacks[cb].isNil:
          ctx.notify(&"Plugin {plg.name} callback `{cb}` failed to load")
          plg.callbacks.del cb

      ctx.notify(&"Loaded {plg.name}: " & toSeq(plg.callbacks.keys()).join(", "))

    ctx.plugins[plg.name] = plg

proc reloadPlugins(ctx: var Ctx) =
  var
    run = true

  while run:
    let
      (ready, data) = gMch[].tryRecv()

    if ready:
      if data.fileExists():
        ctx.loadPlugin(data)
      else:
        ctx.notify(data)
    else:
      run = false

proc handlePluginCommand*(ctx: var Ctx, cmd: string) =
  case cmd:
    of "plugins":
      for pl in ctx.plugins.keys():
        ctx.notify(pl.extractFilename)
    of "unload":
      if ctx.cmdParam.len != 0 and ctx.plugins.hasKey(ctx.cmdParam):
        ctx.unloadPlugin(ctx.cmdParam)
      else:
        for pl in ctx.plugins.keys():
          ctx.unloadPlugin(pl)

  for pl in ctx.plugins.keys():
    if cmd in ctx.plugins[pl].cindex:
      ctx.plugins[pl].callbacks[cmd](ctx.plugins[pl])

proc syncPlugins*(ctx: var Ctx) =
  ctx.reloadPlugins()

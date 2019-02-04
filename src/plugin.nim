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
            (output, exitCode) = execCmdEx(&"nim c --app:lib -o:{dllPath}.new {sourcePath}")
          if exitCode != 0:
            doAssert ch[].trySend(&"{output}\nPlugin compilation failed for {sourcePath}"), "trySend() failure: plugin rebuild failure"
          else:
            doAssert ch[].trySend(&"{dllPath}.new"), "trySend() failure: plugin rebuild"
        elif sourcePath notin loaded:
          loaded.incl sourcePath
          doAssert ch[].trySend(&"{dllPath}"), "trySend() failure: plugin load"

      sleep(5000)

proc initPlugins*(ctx: var Ctx) =
  ctx.plugins = newTable[string, Plugin]()

  gMch = newPtrChannel[string]()
  spawn monitorPlugins(gMch)

proc unloadPlugin(name: string, ctx: var Ctx) =
  if ctx.plugins.hasKey(name):
    if not ctx.plugins[name].onUnload.isNil:
      ctx.plugins[name].onUnload(ctx, ctx.plugins[name])

    ctx.plugins[name].handle.unloadLib()
    ctx.plugins.del(name)

    ctx.notify(&"Unloaded {name}")

proc loadPlugin(dllPath: string, ctx: var Ctx) =
  var
    plugin = new(Plugin)

  if dllPath[^4 .. ^1] == ".new":
    plugin.path = dllPath[0 .. ^5]
    while tryRemoveFile(plugin.path) == false:
      sleep(250)
      echo "Waiting"

    moveFile(dllPath, plugin.path)
  else:
    plugin.path = dllPath

  plugin.name = plugin.path.splitFile().name
  plugin.name.unloadPlugin(ctx)

  plugin.handle = plugin.path.loadLib()
  plugin.cindex.init()
  plugin.callbacks = newTable[string, PCallback]()
  if plugin.handle.isNil:
    ctx.notify(&"Plugin {plugin.name} failed to load")
  else:
    let
      onLoad = cast[PCallback](plugin.handle.symAddr("onLoad"))
    if onLoad.isNil:
      ctx.notify(&"Plugin {plugin.name} does not call 'feudPluginLoad()'")
    else:
      onLoad(ctx, plugin)
      plugin.onUnload = cast[PCallback](plugin.handle.symAddr("onUnload"))
      for cb in plugin.cindex:
        plugin.callbacks[cb] = cast[PCallback](plugin.handle.symAddr(cb))
        if plugin.callbacks[cb].isNil:
          ctx.notify(&"Plugin {plugin.name} callback `{cb}` failed to load")
          plugin.callbacks.del cb

      ctx.notify(&"Loaded {plugin.name}: " & toSeq(plugin.callbacks.keys()).join(", "))

    ctx.plugins[plugin.name] = plugin

proc reloadPlugins(ctx: var Ctx) =
  var
    run = true

  while run:
    let
      (ready, data) = gMch[].tryRecv()

    if ready:
      if data.fileExists():
        data.loadPlugin(ctx)
      else:
        ctx.notify(data)
    else:
      run = false

proc handlePluginCommand*(cmd: string, ctx: var Ctx) =
  case cmd:
    of "plugins":
      for pl in ctx.plugins.keys():
        ctx.notify(pl.extractFilename)
    of "unload":
      if ctx.cmdParam.len != 0 and ctx.plugins.hasKey(ctx.cmdParam):
        unloadPlugin(ctx.cmdParam, ctx)
      else:
        for pl in ctx.plugins.keys():
          unloadPlugin(pl, ctx)

  for pl in ctx.plugins.keys():
    if cmd in ctx.plugins[pl].cindex:
      ctx.plugins[pl].callbacks[cmd](ctx, ctx.plugins[pl])

proc syncPlugins*(ctx: var Ctx) =
  reloadPlugins(ctx)

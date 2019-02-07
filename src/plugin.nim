import dynlib, locks, os, osproc, sequtils, sets, strformat, strutils, tables, threadpool, times

import "."/[globals]

proc dll(sourcePath: string): string =
  let
    (dir, name, _) = sourcePath.splitFile()

  result = dir / (DynlibFormat % name)

proc needsRebuild(sourcePath, dllPath: string): bool =
  if not dllPath.fileExists() or
    sourcePath.getLastModificationTime() > dllPath.getLastModificationTime():
    result = true

proc monitorPlugins(pmonitor: ptr PluginMonitor) {.thread.} =
  while true:
    withLock pmonitor[].lock:
      if not pmonitor[].run:
        break

    for sourcePath in walkFiles("plugins/*.nim"):
      let
        dllPath = sourcePath.dll
        name = sourcePath.splitFile().name
      if sourcePath.needsRebuild(dllPath):
        let
          relbuild =
            when defined(release):
              "-d:release"
            else:
              ""
          (output, exitCode) = execCmdEx(&"nim c --app:lib -o:{dllPath}.new {relbuild} {sourcePath}")
        if exitCode != 0:
          withLock pmonitor[].lock:
            pmonitor[].load.add &"{output}\nPlugin compilation failed for {sourcePath}"
        else:
          withLock pmonitor[].lock:
            if name notin pmonitor[].processed:
              pmonitor[].processed.incl name
            pmonitor[].load.add &"{dllPath}.new"
      else:
        withLock pmonitor[].lock:
          if name notin pmonitor[].processed:
            pmonitor[].processed.incl name
            pmonitor[].load.add &"{dllPath}"

    sleep(5000)

proc initPlugins*(ctx: var Ctx) =
  ctx.plugins = newTable[string, Plugin]()

  ctx.pmonitor = newShared[PluginMonitor]()
  ctx.pmonitor[].lock.initLock()
  ctx.pmonitor[].run = true

  ctx.pmonitor[].load = @[]
  ctx.pmonitor[].processed.init()

  spawn monitorPlugins(ctx.pmonitor)

proc unloadPlugin(ctx: var Ctx, name: string) =
  if ctx.plugins.hasKey(name):
    if not ctx.plugins[name].onUnload.isNil:
      try:
        ctx.plugins[name].onUnload(ctx.plugins[name])
      except:
        ctx.notify(&"Plugin '{name}' crashed in 'feudPluginUnload()'")

    ctx.plugins[name].handle.unloadLib()
    ctx.plugins.del(name)

    ctx.notify(&"Plugin '{name}' unloaded")

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
      ctx.notify("Plugin '{plg.name}' failed to unload")
      return

    moveFile(dllPath, plg.path)

  plg.handle = plg.path.loadLib()
  plg.cindex.init()
  plg.callbacks = newTable[string, PCallback]()
  if plg.handle.isNil:
    ctx.notify(&"Plugin '{plg.name}' failed to load")
  else:
    let
      onLoad = cast[PCallback](plg.handle.symAddr("onLoad"))
    if onLoad.isNil:
      ctx.notify(&"Plugin '{plg.name}' missing 'feudPluginLoad()'")
    else:
      try:
        plg.onLoad()
      except:
        ctx.notify(&"Plugin '{plg.name}' crashed in 'feudPluginLoad()'")
        return

      plg.onUnload = cast[PCallback](plg.handle.symAddr("onUnload"))
      plg.onTick = cast[PCallback](plg.handle.symAddr("onTick"))

      for cb in plg.cindex:
        plg.callbacks[cb] = cast[PCallback](plg.handle.symAddr(cb))
        if plg.callbacks[cb].isNil:
          ctx.notify(&"Plugin '{plg.name}' callback '{cb}' failed to load")
          plg.callbacks.del cb

      ctx.notify(&"Plugin '{plg.name}' loaded (" & toSeq(plg.callbacks.keys()).join(", ") & ")")

    ctx.plugins[plg.name] = plg

proc stopPlugins*(ctx: var Ctx) =
  withLock ctx.pmonitor[].lock:
    ctx.pmonitor[].run = false

  for pl in ctx.plugins.keys():
    ctx.unloadPlugin(pl)

  freeShared(ctx.pmonitor)

proc reloadPlugins(ctx: var Ctx) =
  withLock ctx.pmonitor[].lock:
    for i in ctx.pmonitor[].load:
      if i.fileExists():
        ctx.loadPlugin(i)
      else:
        ctx.notify(i)
    ctx.pmonitor[].load = @[]

proc tickPlugins(ctx: var Ctx) =
  for pl in ctx.plugins.keys():
    var
      plg = ctx.plugins[pl]
    if not plg.onTick.isNil:
      try:
        plg.onTick(plg)
      except:
        ctx.notify(&"Plugin '{plg.name}' crashed in 'feudPluginTick()'")
        ctx.unloadPlugin(plg.name)

proc handlePluginCommand*(ctx: var Ctx, cmd: string) =
  case cmd:
    of "plugins":
      for pl in ctx.plugins.keys():
        ctx.notify(pl.extractFilename)
    of "reload", "load":
      if ctx.cmdParam.len != 0:
        if ctx.plugins.hasKey(ctx.cmdParam):
          withLock ctx.pmonitor[].lock:
            ctx.pmonitor[].processed.excl ctx.cmdParam
      else:
        withLock ctx.pmonitor[].lock:
          ctx.pmonitor[].processed.clear()
    of "unload":
      if ctx.cmdParam.len != 0:
        if ctx.plugins.hasKey(ctx.cmdParam):
          ctx.unloadPlugin(ctx.cmdParam)
        else:
          ctx.notify(&"Plugin '{ctx.cmdParam}' not found")
      else:
        for pl in ctx.plugins.keys():
          ctx.unloadPlugin(pl)

  for pl in ctx.plugins.keys():
    var
      plg = ctx.plugins[pl]
    if cmd in plg.cindex:
      try:
        plg.callbacks[cmd](plg)
      except:
        ctx.notify(&"Plugin '{plg.name}' crashed in '{cmd}()'")

proc syncPlugins*(ctx: var Ctx) =
  ctx.reloadPlugins()
  ctx.tickPlugins()

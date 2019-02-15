import dynlib, locks, os, osproc, sequtils, sets, strformat, strutils, tables, threadpool, times

when defined(Windows):
  import winim/inc/[windef, winuser]

import "."/[globals, utils]

proc dll(sourcePath: string): string =
  let
    (dir, name, _) = sourcePath.splitFile()

  result = dir / (DynlibFormat % name)

proc monitorPlugins(pmonitor: ptr PluginMonitor) {.thread.} =
  var
    path = ""
    base = getAppDir()/"plugins"

  withLock pmonitor[].lock:
    path = pmonitor[].path

  while true:
    withLock pmonitor[].lock:
      if not pmonitor[].run:
        break

    var
      sourcePaths = toSeq(walkFiles(base/"*.nim"))
    sourcePaths.add toSeq(walkFiles(base/path/"*.nim"))

    for sourcePath in sourcePaths:
      let
        dllPath = sourcePath.dll
        dllPathNew = dllPath & ".new"
        name = sourcePath.splitFile().name

      if not dllPath.fileExists() or
        sourcePath.getLastModificationTime() > dllPath.getLastModificationTime():
        var
          relbuild =
            when defined(release):
              "-d:release"
            else:
              ""
          output = ""
          exitCode = 0

        if not dllPathNew.fileExists() or
          sourcePath.getLastModificationTime() > dllPathNew.getLastModificationTime():
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

    sleep(2000)

proc unloadPlugin(ctx: var Ctx, name: string) =
  if ctx.plugins.hasKey(name) and ctx.plugins[name].dependents.len == 0:
    if not ctx.plugins[name].onUnload.isNil:
      try:
        ctx.plugins[name].onUnload(ctx.plugins[name])
      except:
        ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{name}' crashed in 'feudPluginUnload()'")

    ctx.plugins[name].handle.unloadLib()
    for dep in ctx.plugins[name].depends:
      if ctx.plugins.hasKey(dep):
        ctx.plugins[dep].dependents.excl name
    ctx.plugins[name] = nil
    ctx.plugins.del(name)

    ctx.notify(ctx, &"Plugin '{name}' unloaded")

proc notifyPlugins*(ctx: var Ctx) =
  var
    notified = false
  for pl in ctx.plugins.keys():
    var
      plg = ctx.plugins[pl]
    if not plg.onNotify.isNil:
      try:
        plg.onNotify(plg)
        notified = true
      except:
        ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginNotify()'")
        ctx.unloadPlugin(plg.name)

  # if not notified:
  if ctx.cmdParam.len != 0:
    echo ctx.cmdParam[0]

  ctx.cmdParam = @[]

proc initPlugins*(ctx: var Ctx, path: string) =
  ctx.plugins = newTable[string, Plugin]()
  ctx.pluginData = newTable[string, pointer]()

  ctx.pmonitor = newShared[PluginMonitor]()
  ctx.pmonitor[].lock.initLock()
  ctx.pmonitor[].run = true
  ctx.pmonitor[].path = path

  ctx.pmonitor[].load = @[]
  ctx.pmonitor[].processed.init()

  ctx.notify = proc(ctx: var Ctx, msg: string) =
    ctx.cmdParam = @[msg]
    ctx.notifyPlugins()

  spawn monitorPlugins(ctx.pmonitor)

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
      ctx.notify(ctx, &"Plugin '{plg.name}' failed to unload")
      return

    try:
      moveFile(dllPath, plg.path)
    except:
      ctx.notify(ctx, &"Plugin '{plg.name}' dll copy failed")
      return

  plg.handle = plg.path.loadLib()
  sleep(100)
  plg.cindex.init()
  plg.dependents.init()
  plg.callbacks = newTable[string, PCallback]()

  if plg.handle.isNil:
    ctx.notify(ctx, &"Plugin '{plg.name}' failed to load")
    return
  else:
    let
      onDepends = cast[PCallback](plg.handle.symAddr("onDepends"))

    if not onDepends.isNil:
      try:
        plg.onDepends()
      except:
        ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginDepends()'")
        plg.handle.unloadLib()
        return

      for dep in plg.depends:
        if not ctx.plugins.hasKey(dep):
          ctx.notify(ctx, &"Plugin '{plg.name}' dependency '{dep}' not loaded")
          withLock ctx.pmonitor[].lock:
            ctx.pmonitor[].processed.excl plg.name
          plg.handle.unloadLib()
          return

    let
      onLoad = cast[PCallback](plg.handle.symAddr("onLoad"))

    if onLoad.isNil:
      ctx.notify(ctx, &"Plugin '{plg.name}' missing 'feudPluginLoad()'")
      plg.handle.unloadLib()
    else:
      try:
        plg.onLoad()
      except:
        ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginLoad()'")
        plg.handle.unloadLib()
        return

      plg.onUnload = cast[PCallback](plg.handle.symAddr("onUnload"))
      plg.onTick = cast[PCallback](plg.handle.symAddr("onTick"))
      plg.onNotify = cast[PCallback](plg.handle.symAddr("onNotify"))

      for cb in plg.cindex:
        plg.callbacks[cb] = cast[PCallback](plg.handle.symAddr(cb))
        if plg.callbacks[cb].isNil:
          ctx.notify(ctx, &"Plugin '{plg.name}' callback '{cb}' failed to load")
          plg.callbacks.del cb

      ctx.plugins[plg.name] = plg

      for dep in plg.depends:
        if ctx.plugins.hasKey(dep):
          ctx.plugins[dep].dependents.incl plg.name

      ctx.notify(ctx, &"Plugin '{plg.name}' loaded (" & toSeq(plg.callbacks.keys()).join(", ") & ")")

proc stopPlugins*(ctx: var Ctx) =
  withLock ctx.pmonitor[].lock:
    ctx.pmonitor[].run = false

  while ctx.plugins.len != 0:
    for pl in ctx.plugins.keys():
      ctx.unloadPlugin(pl)

  freeShared(ctx.pmonitor)

proc reloadPlugins(ctx: var Ctx) =
  withLock ctx.pmonitor[].lock:
    for i in ctx.pmonitor[].load:
      if i.fileExists():
        ctx.loadPlugin(i)
      else:
        ctx.notify(ctx, i)
    ctx.pmonitor[].load = @[]

proc tickPlugins(ctx: var Ctx) =
  for pl in ctx.plugins.keys():
    var
      plg = ctx.plugins[pl]
    if not plg.onTick.isNil:
      try:
        plg.onTick(plg)
      except:
        ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginTick()'")
        ctx.unloadPlugin(plg.name)

proc handlePluginCommand*(ctx: var Ctx, cmd: string): bool =
  result = true
  case cmd:
    of "plugins":
      var
        nf = ""
      for pl in ctx.plugins.keys():
        nf &= pl.extractFilename & " "
      ctx.notify(ctx, nf)
    of "reload", "load":
      if ctx.cmdParam.len != 0:
        withLock ctx.pmonitor[].lock:
          ctx.pmonitor[].processed.excl ctx.cmdParam[0]
      else:
        withLock ctx.pmonitor[].lock:
          ctx.pmonitor[].processed.clear()
    of "unload":
      if ctx.cmdParam.len != 0:
        if ctx.plugins.hasKey(ctx.cmdParam[0]):
          ctx.unloadPlugin(ctx.cmdParam[0])
        else:
          ctx.notify(ctx, &"Plugin '{ctx.cmdParam[0]}' not found")
      else:
        for pl in ctx.plugins.keys():
          ctx.unloadPlugin(pl)
    else:
      result = false
      for pl in ctx.plugins.keys():
        var
          plg = ctx.plugins[pl]
        if cmd in plg.cindex:
          result = true
          try:
            plg.callbacks[cmd](plg)
          except:
            ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in '{cmd}()'")
          break

proc syncPlugins*(ctx: var Ctx) =
  ctx.reloadPlugins()
  ctx.tickPlugins()

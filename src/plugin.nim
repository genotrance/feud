import dynlib, locks, os, osproc, sequtils, sets, strformat, strutils, tables, times

when defined(Windows):
  import winim/inc/[windef, winuser]

import "."/[globals, utils]

var
  gThread: Thread[ptr PluginMonitor]

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

proc hasCallback(plg: var Plugin, name: string): bool {.inline.} =
  return plg.callbacks.hasKey(name) and not plg.callbacks[name].isNil

proc unloadPlugin(ctx: var Ctx, name: string) =
  if ctx.plugins.hasKey(name) and ctx.plugins[name].dependents.len == 0:
    if ctx.plugins[name].hasCallback("onUnload"):
      try:
        ctx.plugins[name].callbacks["onUnload"](ctx.plugins[name])
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
    if plg.hasCallback("onNotify"):
      try:
        plg.callbacks["onNotify"](plg)
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

  createThread(gThread, monitorPlugins, ctx.pmonitor)

proc initPlugin(plg: var Plugin) =
  if not plg.hasCallback("onLoad"):
    var
      once = false

    if not plg.hasCallback("onDepends"):
      once = true
      plg.callbacks["onDepends"] = plg.handle.symAddr("onDepends").toCallback()

      if plg.hasCallback("onDepends"):
        try:
          plg.callbacks["onDepends"](plg)
        except:
          plg.ctx.notify(plg.ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginDepends()'")
          plg.ctx.unloadPlugin(plg.name)
          return

    for dep in plg.depends:
      if not plg.ctx.plugins.hasKey(dep):
        if once:
          plg.ctx.notify(plg.ctx, &"Plugin '{plg.name}' dependency '{dep}' not loaded")
        withLock plg.ctx.pmonitor[].lock:
          plg.ctx.pmonitor[].init.add plg.name
        return

    plg.callbacks["onLoad"] = plg.handle.symAddr("onLoad").toCallback()
    if not plg.hasCallback("onLoad"):
      plg.ctx.notify(plg.ctx, &"Plugin '{plg.name}' missing 'feudPluginLoad()'")
      plg.ctx.unloadPlugin(plg.name)
    else:
      try:
        plg.callbacks["onLoad"](plg)
      except:
        plg.ctx.notify(plg.ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginLoad()'")
        plg.ctx.unloadPlugin(plg.name)
        return

      plg.callbacks["onUnload"] = plg.handle.symAddr("onUnload").toCallback()
      plg.callbacks["onTick"] = plg.handle.symAddr("onTick").toCallback()
      plg.callbacks["onNotify"] = plg.handle.symAddr("onNotify").toCallback()

      for cb in plg.cindex:
        plg.callbacks[cb] = plg.handle.symAddr(cb).toCallback()
        if plg.callbacks[cb].isNil:
          plg.ctx.notify(plg.ctx, &"Plugin '{plg.name}' callback '{cb}' failed to load")
          plg.callbacks.del cb

      for dep in plg.depends:
        if plg.ctx.plugins.hasKey(dep):
          plg.ctx.plugins[dep].dependents.incl plg.name

      plg.ctx.notify(plg.ctx, &"Plugin '{plg.name}' loaded (" & toSeq(plg.callbacks.keys()).join(", ") & ")")

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
  plg.cindex.init()
  plg.dependents.init()
  plg.callbacks = newTable[string, proc(plg: var Plugin)]()

  if plg.handle.isNil:
    ctx.notify(ctx, &"Plugin '{plg.name}' failed to load")
    return
  else:
    ctx.plugins[plg.name] = plg

    plg.initPlugin()

proc stopPlugins*(ctx: var Ctx) =
  withLock ctx.pmonitor[].lock:
    ctx.pmonitor[].run = false

  while ctx.plugins.len != 0:
    for pl in ctx.plugins.keys():
      ctx.unloadPlugin(pl)

  gThread.joinThread()

  freeShared(ctx.pmonitor)

proc reloadPlugins(ctx: var Ctx) =
  var
    load: seq[string]
    init: seq[string]

  withLock ctx.pmonitor[].lock:
    load = ctx.pmonitor[].load
    init = ctx.pmonitor[].init

    ctx.pmonitor[].load = @[]
    ctx.pmonitor[].init = @[]

  for i in load:
    if i.fileExists():
      ctx.loadPlugin(i)
    else:
      ctx.notify(ctx, i)

  for i in init:
    if ctx.plugins.hasKey(i):
      ctx.plugins[i].initPlugin()

proc tickPlugins(ctx: var Ctx) =
  for pl in ctx.plugins.keys():
    var
      plg = ctx.plugins[pl]
    if plg.hasCallback("onTick"):
      try:
        plg.callbacks["onTick"](plg)
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
  ctx.tick += 1
  if ctx.tick == 25:
    ctx.tick = 0
    ctx.reloadPlugins()

  ctx.tickPlugins()

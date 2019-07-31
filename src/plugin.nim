import shared/seq

import dynlib, locks, os, osproc, sequtils, sets, strformat, strutils, tables, times

when defined(Windows):
  import winim/inc/[windef, winuser]

import "."/[globals, utils]

var
  gThread: Thread[ptr PluginMonitor]

template tryCatch(body: untyped) {.dirty.} =
  var
    ret {.inject.} = true
  try:
    body
  except:
    when not defined(release):
      echo getStackTrace().strip()
    ret = false

when not defined(binary):
  proc dll(sourcePath: string): string =
    let
      (dir, name, _) = sourcePath.splitFile()

    result = dir / (DynlibFormat % name)

  proc sourceChanged(sourcePath, dllPath: string): bool =
    let
      dllTime = dllPath.getLastModificationTime()

    if sourcePath.getLastModificationTime() > dllTime:
      result = true
    else:
      let
        depDir = sourcePath.parentDir() / sourcePath.splitFile().name

      if depDir.dirExists():
        for dep in toSeq(walkFiles(depDir/"*.nim")):
          if dep.getLastModificationTime() > dllTime:
            result = true
            break

proc monitorPlugins(pmonitor: ptr PluginMonitor) {.thread.} =
  var
    path = ""
    base = getAppDir()/"plugins"
    delay = 200

  withLock pmonitor[].lock:
    path = $(pmonitor[].mode)

  while true:
    defer:
      sleep(delay)

    let
      ext =
        when defined(binary):
          "dll"
        else:
          "nim"

    var
      xPaths = toSeq(walkFiles(base/"*." & ext))
    xPaths.add toSeq(walkFiles(base/path/"*." & ext))

    withLock pmonitor[].lock:
      case pmonitor[].run
      of paused:
        continue
      of stopped:
        break
      else:
        discard

      if not pmonitor[].ready and pmonitor[].processed.len == xPaths.len:
        pmonitor[].ready = true
        delay = 2000

    let
      allowF = base/"allow.ini"
      blockF = base/"block.ini"
      allowed =
        if allowF.fileExists():
          allowF.readFile().splitLines()
        else:
          @[]
      blocked =
        if blockF.fileExists():
          blockF.readFile().splitLines()
        else:
          @[]

    when defined(binary):
      for dllPath in xPaths:
        let
          name = dllPath.splitFile().name

        withLock pmonitor[].lock:
          if (allowed.len != 0 and name notin allowed) or
              (blocked.len != 0 and name in blocked):
            if name notin pmonitor[].processed:
              pmonitor[].processed.add name
            continue

          if name notin pmonitor[].processed:
            pmonitor[].processed.add name
            pmonitor[].load.add &"{dllPath}"
    else:
      for sourcePath in xPaths:
        let
          dllPath = sourcePath.dll
          dllPathNew = dllPath & ".new"
          name = sourcePath.splitFile().name

        if (allowed.len != 0 and name notin allowed) or
            (blocked.len != 0 and name in blocked):
          withLock pmonitor[].lock:
            if name notin pmonitor[].processed:
              pmonitor[].processed.add name
          continue

        if not dllPath.fileExists() or sourcePath.sourceChanged(dllPath):
          var
            relbuild =
              when defined(release):
                "--opt:speed"
              else:
                "--debugger:native --debuginfo -d:useGcAssert -d:useSysAssert"
            output = ""
            exitCode = 0

          if not dllPathNew.fileExists() or
            sourcePath.getLastModificationTime() > dllPathNew.getLastModificationTime():
            (output, exitCode) = execCmdEx(&"nim c --app:lib -o:{dllPath}.new {relbuild} {sourcePath}")
          if exitCode != 0:
            pmonitor[].load.add &"{output}\nPlugin compilation failed for {sourcePath}"
          else:
            withLock pmonitor[].lock:
              if name notin pmonitor[].processed:
                pmonitor[].processed.add name
              pmonitor[].load.add &"{dllPath}.new"
        else:
          withLock pmonitor[].lock:
            if name notin pmonitor[].processed:
              pmonitor[].processed.add name
              pmonitor[].load.add &"{dllPath}"

proc unloadPlugin(ctx: var Ctx, name: string) =
  if ctx.plugins.hasKey(name):
    for dep in ctx.plugins[name].dependents:
      ctx.notify(ctx, &"Plugin '{dep}' depends on '{name}' and might crash")

    if not ctx.plugins[name].onUnload.isNil:
      var
        cmd = new(CmdData)
      tryCatch:
        ctx.plugins[name].onUnload(ctx.plugins[name], cmd)
      if not ret:
        ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{name}' crashed in 'feudPluginUnload()'")
      if cmd.failed:
        ctx.notify(ctx, &"Plugin '{name}' failed in 'feudPluginUnload()'")

    ctx.plugins[name].handle.unloadLib()
    for dep in ctx.plugins[name].depends:
      if ctx.plugins.hasKey(dep):
        ctx.plugins[dep].dependents.excl name
    ctx.plugins[name] = nil
    ctx.plugins.del(name)

    ctx.notify(ctx, &"Plugin '{name}' unloaded")

proc notifyPlugins*(ctx: var Ctx, cmd: var CmdData) =
  let
    pkeys = toSeq(ctx.plugins.keys())
  for pl in pkeys:
    var
      plg = ctx.plugins[pl]
    cmd.failed = false
    if not plg.onNotify.isNil:
      tryCatch:
        plg.onNotify(plg, cmd)
      if not ret:
        plg.onNotify = nil
        ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginNotify()'")
        ctx.unloadPlugin(plg.name)
      if cmd.failed:
        ctx.notify(ctx, &"Plugin '{plg.name}' failed in 'feudPluginNotify()'")

  echo cmd.params[0]

proc initPlugins*(ctx: var Ctx, mode: PluginMode) =
  ctx.pmonitor = newShared[PluginMonitor]()
  ctx.pmonitor[].lock.initLock()
  ctx.pmonitor[].run = executing
  ctx.pmonitor[].mode = mode

  ctx.notify = proc(ctx: var Ctx, msg: string) =
    var
      cmd = new(CmdData)
    cmd.params.add msg
    ctx.notifyPlugins(cmd)

  createThread(gThread, monitorPlugins, ctx.pmonitor)

  var
    cmd = newCmdData("version")
  ctx.handleCommand(ctx, cmd)

proc initPlugin(plg: var Plugin) =
  if plg.onLoad.isNil:
    var
      once = false
      cmd: CmdData

    if plg.onDepends.isNil:
      once = true
      plg.onDepends = plg.handle.symAddr("onDepends").toCallback()

      if not plg.onDepends.isNil:
        cmd = new(CmdData)
        tryCatch:
          plg.onDepends(plg, cmd)
        if not ret:
          plg.ctx.notify(plg.ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginDepends()'")
          plg.ctx.unloadPlugin(plg.name)
          return
        if cmd.failed:
          plg.ctx.notify(plg.ctx, &"Plugin '{plg.name}' failed in 'feudPluginDepends()'")
          plg.ctx.unloadPlugin(plg.name)
          return

    for dep in plg.depends:
      if not plg.ctx.plugins.hasKey(dep):
        if once:
          plg.ctx.notify(plg.ctx, &"Plugin '{plg.name}' dependency '{dep}' not loaded")
        return

    plg.onLoad = plg.handle.symAddr("onLoad").toCallback()
    if plg.onLoad.isNil:
      plg.ctx.notify(plg.ctx, &"Plugin '{plg.name}' missing 'feudPluginLoad()'")
      plg.ctx.unloadPlugin(plg.name)
    else:
      cmd = new(CmdData)
      tryCatch:
        plg.onLoad(plg, cmd)
      if not ret:
        plg.ctx.notify(plg.ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginLoad()'")
        plg.ctx.unloadPlugin(plg.name)
        return
      if cmd.failed:
        plg.ctx.notify(plg.ctx, &"Plugin '{plg.name}' failed in 'feudPluginLoad()'")
        plg.ctx.unloadPlugin(plg.name)
        return

      plg.onUnload = plg.handle.symAddr("onUnload").toCallback()
      plg.onTick = plg.handle.symAddr("onTick").toCallback()
      plg.onNotify = plg.handle.symAddr("onNotify").toCallback()

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

    tryCatch:
      moveFile(dllPath, plg.path)
    if not ret:
      ctx.notify(ctx, &"Plugin '{plg.name}' dll copy failed")
      return

  plg.handle = plg.path.loadLib()
  plg.cindex.init()
  plg.dependents.init()

  if plg.handle.isNil:
    ctx.notify(ctx, &"Plugin '{plg.name}' failed to load")
    return
  else:
    ctx.plugins[plg.name] = plg

    plg.initPlugin()

proc stopPlugins*(ctx: var Ctx) =
  withLock ctx.pmonitor[].lock:
    ctx.pmonitor[].run = stopped

  while ctx.plugins.len != 0:
    let
      pkeys = toSeq(ctx.plugins.keys())
    for pl in pkeys:
      ctx.unloadPlugin(pl)

  gThread.joinThread()

  ctx.pmonitor[].load.free()
  ctx.pmonitor[].processed.free()

  freeShared(ctx.pmonitor)

proc reloadPlugins(ctx: var Ctx) =
  var
    load: seq[string]

  withLock ctx.pmonitor[].lock:
    load = ctx.pmonitor[].load.toSequence()

    ctx.pmonitor[].load.clear()

  for i in load:
    if i.fileExists():
      ctx.loadPlugin(i)
    else:
      ctx.notify(ctx, i)

  for i in ctx.plugins.keys():
    if ctx.plugins[i].onLoad.isNil:
      ctx.plugins[i].initPlugin()

proc tickPlugins(ctx: var Ctx) =
  let
    pkeys = toSeq(ctx.plugins.keys())
  for pl in pkeys:
    var
      plg = ctx.plugins[pl]
      cmd = new(CmdData)
    if not plg.onTick.isNil:
      tryCatch:
        plg.onTick(plg, cmd)
      if not ret:
        ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in 'feudPluginTick()'")
        ctx.unloadPlugin(plg.name)
      if cmd.failed:
        ctx.notify(ctx, &"Plugin '{plg.name}' failed in 'feudPluginTick()'")

proc getVersion(): string =
  const
    execResult = gorgeEx("git rev-parse HEAD")
  when execResult[0].len > 0 and execResult[1] == 0:
    result = execResult[0].strip()
  else:
    result ="couldn't determine git hash"

proc handlePluginCommand*(ctx: var Ctx, cmd: var CmdData) =
  if cmd.params.len == 0:
    cmd.failed = true
    return

  case cmd.params[0]:
    of "plist":
      var
        nf = ""
      for pl in ctx.plugins.keys():
        nf &= pl.extractFilename & " "
      ctx.notify(ctx, nf)
    of "preload", "pload":
      if cmd.params.len > 1:
        withLock ctx.pmonitor[].lock:
          for i in 1 .. cmd.params.len-1:
            ctx.pmonitor[].processed.remove cmd.params[i]
      else:
        ctx.pmonitor[].processed.clear()
    of "punload":
      if cmd.params.len > 1:
        for i in 1 .. cmd.params.len-1:
          if ctx.plugins.hasKey(cmd.params[i]):
            ctx.unloadPlugin(cmd.params[i])
          else:
            ctx.notify(ctx, &"Plugin '{cmd.params[i]}' not found")
      else:
        let
          pkeys = toSeq(ctx.plugins.keys())
        for pl in pkeys:
          ctx.unloadPlugin(pl)
    of "presume":
      withLock ctx.pmonitor[].lock:
        ctx.pmonitor[].run = executing
      ctx.notify(ctx, &"Plugin monitor resumed")
    of "ppause":
      withLock ctx.pmonitor[].lock:
        ctx.pmonitor[].run = paused
      ctx.notify(ctx, &"Plugin monitor paused")
    of "pstop":
      withLock ctx.pmonitor[].lock:
        ctx.pmonitor[].run = stopped
      ctx.notify(ctx, &"Plugin monitor exited")
    of "version":
      ctx.notify(ctx,
        &"Feud {getVersion()}\ncompiled on {CompileDate} {CompileTime} with Nim v{NimVersion}")
    else:
      cmd.failed = true
      let
        pkeys = toSeq(ctx.plugins.keys())
      for pl in pkeys:
        var
          plg = ctx.plugins[pl]
          ccmd = new(CmdData)
        ccmd.params = cmd.params[1 .. ^1]
        if cmd.params[0] in plg.cindex:
          tryCatch:
            plg.callbacks[cmd.params[0]](plg, ccmd)
          if not ret:
            ctx.notify(ctx, getCurrentExceptionMsg() & &"Plugin '{plg.name}' crashed in '{cmd.params[0]}()'")
          elif ccmd.failed:
            ctx.notify(ctx, &"Plugin '{plg.name}' failed in '{cmd.params[0]}()'")
          else:
            cmd.returned &= ccmd.returned
            cmd.failed = false
          break

proc handleCli(ctx: var Ctx) =
  if ctx.cli.len != 0:
    for command in ctx.cli:
      var
        cmd = newCmdData(command)
      ctx.handleCommand(ctx, cmd)
    ctx.cli = @[]

proc handleReady(ctx: var Ctx) =
  if not ctx.ready:
    withLock ctx.pmonitor[].lock:
      if ctx.pmonitor[].ready:
        ctx.ready = true
        var
          cmd = newCmdData("runHook onReady")
        ctx.handleCommand(ctx, cmd)
        ctx.handleCli()

proc syncPlugins*(ctx: var Ctx) =
  ctx.tick += 1
  if not ctx.ready or ctx.tick == 25:
    ctx.tick = 0
    ctx.reloadPlugins()
    ctx.handleReady()

  ctx.tickPlugins()

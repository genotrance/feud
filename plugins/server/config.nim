import os, strformat, strutils, tables

import "../../src"/pluginapi

type
  Config = ref object
    commands: seq[string]
    hooks: TableRef[string, seq[string]]

let
  baseName = "feud.ini"
  configFiles = @[
    getAppDir()/baseName
  ]

proc getConfig(plg: var Plugin): Config =
  return getCtxData[Config](plg)

proc loadConfigFile(plg: var Plugin) =
  var
    config = plg.getConfig()

  for cfgFile in configFiles:
    if fileExists(cfgFile):
      for line in cfgFile.readFile().splitLines():
        let
          sline = line.strip()
        if sline.len != 0 and sline[0] notin ['#', ';']:
          config.commands.add sline

proc execConfig(plg: var Plugin) =
  var
    config = plg.getConfig()

  if config.commands.len != 0:
    var
      done: seq[int] = @[]

    for i in 0 .. config.commands.len-1:
      if plg.ctx.handleCommand(plg.ctx, config.commands[i]):
        plg.ctx.notify(plg.ctx, config.commands[i])
        done.add i

    for i in countdown(done.len-1, 0):
      config.commands.delete done[i]

proc config(plg: var Plugin) {.feudCallback.} =
  var
    config = plg.getConfig()

  config.commands = @["hook postWindowLoad config"]
  config.hooks = newTable[string, seq[string]]()

  plg.loadConfigFile()

proc hook(plg: var Plugin) {.feudCallback.} =
  var
    config = plg.getConfig()

  for param in plg.getParam():
    let
      (hname, hval) = param.splitCmd()

    if hname.len != 0 and hval.len != 0:
      if config.hooks.hasKey(hname):
        if hval notin config.hooks[hname]:
          config.hooks[hname].add hval
      else:
        config.hooks[hname] = @[hval]

proc runHook(plg: var Plugin) {.feudCallback.} =
  var
    config = plg.getConfig()

  for param in plg.getParam():
    let
      (hook, opts) = param.splitCmd()
    if config.hooks.hasKey(hook):
      for cmd in config.hooks[hook]:
        if opts.len != 0:
          discard plg.ctx.handleCommand(plg.ctx, &"{cmd} {opts}")
        else:
          discard plg.ctx.handleCommand(plg.ctx, cmd)

proc delHook(plg: var Plugin) {.feudCallback.} =
  var
    config = plg.getConfig()

  for param in plg.getParam():
    if config.hooks.hasKey(param):
      config.hooks.del(param)

proc script(plg: var Plugin) {.feudCallback.} =
  for params in plg.getParam():
    let
      params = params.split(" ")
    for param in params:
      let
        param = param.strip()
      if param.len != 0 and param.fileExists():
        for line in param.readFile().splitLines():
          let
            sline = line.strip()
          if sline.len != 0 and sline[0] notin ['#', ';']:
            discard plg.ctx.handleCommand(plg.ctx, sline)
            plg.ctx.notify(plg.ctx, sline)

feudPluginLoad:
  plg.config()

feudPluginTick:
  if plg.ctx.tick == 0:
    plg.execConfig()
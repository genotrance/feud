import os, strutils

import "../../src"/pluginapi

type
  Config = ref object
    commands: seq[string]

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
        if sline.len != 0:
          config.commands.add sline

proc loadConfig(plg: var Plugin) =
  var
    config = plg.getConfig()

  if config.commands.len != 0:
    var
      done: seq[int] = @[]

    for i in 0 .. config.commands.len-1:
      if plg.ctx.handleCommand(plg.ctx, config.commands[i]):
        plg.ctx.notify(plg.ctx, "Config: " & config.commands[i])
        done.add i

    for i in countdown(done.len-1, 0):
      config.commands.delete done[i]

proc config(plg: var Plugin) {.feudCallback.} =
  var
    config = plg.getConfig()

  config.commands = @[]

  plg.loadConfigFile()
  plg.loadConfig()

feudPluginLoad:
  plg.config()

feudPluginTick:
  if plg.ctx.tick mod 50 == 0:
    plg.loadConfig()
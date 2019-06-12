import os, strformat, strutils, tables

import "../../src"/pluginapi

type
  Config = ref object
    commands: seq[string]
    hooks: TableRef[string, seq[string]]
    settings: TableRef[string, string]

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
      cmd: CmdData

    for i in 0 .. config.commands.len-1:
      cmd = newCmdData(config.commands[i])
      plg.ctx.handleCommand(plg.ctx, cmd)
      if not cmd.failed:
        plg.ctx.notify(plg.ctx, config.commands[i])
        done.add i

    for i in countdown(done.len-1, 0):
      config.commands.delete done[i]

proc config(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    config = plg.getConfig()

  config.commands = @[]
  config.hooks = newTable[string, seq[string]]()
  config.settings = newTable[string, string]()

  plg.loadConfigFile()

proc hook(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    config = plg.getConfig()

  if cmd.params.len > 1:
    let
      hname = cmd.params[0]
      hval = cmd.params[1 .. ^1].join(" ")
    if config.hooks.hasKey(hname):
      if hval notin config.hooks[hname]:
        config.hooks[hname].add hval
    else:
      config.hooks[hname] = @[hval]
  elif cmd.params.len == 1:
    let
      hname = cmd.params[0]
    if config.hooks.hasKey(hname):
      var
        outp = ""
      for hval in config.hooks[hname]:
        outp &= hval & ", "
      if outp.len > 2:
        plg.ctx.notify(plg.ctx, hname & ": " & outp[0 .. ^3])
  elif cmd.params.len == 0:
    for key in config.hooks.keys:
      var
        ccmd = newCmdData("hook " & key)
      plg.ctx.handleCommand(plg.ctx, ccmd)

proc runHook(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    config = plg.getConfig()

  if cmd.params.len != 0:
    let
      hook = cmd.params[0]
    if config.hooks.hasKey(hook):
      for command in config.hooks[hook]:
        var
          cmd = newCmdData(
            if cmd.params.len > 1:
              &"""{command} {cmd.params[1 .. ^1].join(" ")}"""
            else:
              command
          )
        plg.ctx.handleCommand(plg.ctx, cmd)

proc delHook(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    config = plg.getConfig()

  if cmd.params.len == 1:
    if config.hooks.hasKey(cmd.params[0]):
      config.hooks.del(cmd.params[0])

proc script(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  for param in cmd.params:
    if param.fileExists():
      for line in param.readFile().splitLines():
        let
          sline = line.strip()
        if sline.len != 0 and sline[0] notin ['#', ';']:
          var
            cmd = newCmdData(sline)
          plg.ctx.handleCommand(plg.ctx, cmd)
          plg.ctx.notify(plg.ctx, sline)

proc get(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  if cmd.params.len != 0:
    var
      config = plg.getConfig()
      name = cmd.params[0]

    if config.settings.hasKey(name):
      cmd.returned = @[config.settings[name]]

proc set(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  if cmd.params.len > 0:
    var
      config = plg.getConfig()
      sname = cmd.params[0]
    if cmd.params.len > 1:
      config.settings[sname] = cmd.params[1 .. ^1].join(" ")
    else:
      if config.settings.hasKey(sname):
        config.settings.del(sname)

feudPluginLoad:
  plg.config(cmd)

feudPluginTick:
  if plg.ctx.tick == 0:
    plg.execConfig()
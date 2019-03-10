import sets, strformat, strutils, tables

import "../../src"/pluginapi

type
  Aliases = ref object
    atable: TableRef[string, string]

proc getAliases(plg: var Plugin): Aliases =
  return getCtxData[Aliases](plg)

proc setupAlias(plg: var Plugin, alias: string) =
  var
    aliases = plg.getAliases()

  if not plg.callbacks.hasKey(alias):
    plg.cindex.incl alias
    plg.callbacks[alias] = proc(plg: var Plugin) =
      var
        cmd = aliases.atable[alias]

      for param in plg.getParam():
        discard plg.ctx.handleCommand(plg.ctx, &"{cmd} {param}")

proc alias(plg: var Plugin) {.feudCallback.} =
  var
    aliases = plg.getAliases()

  if plg.ctx.cmdParam.len == 0:
    var aout = ""

    for alias in aliases.atable.keys():
      aout &= &"{alias} = {aliases.atable[alias]}\n"

    if aout.len != 0:
      plg.ctx.notify(plg.ctx, aout[0 .. ^2])
  else:
    for param in plg.getParam():
      let
        (alias, val) = param.splitCmd()

      if val.len != 0:
        aliases.atable[alias] = val
        plg.setupAlias(alias)
      else:
        aliases.atable.del(alias)
        plg.cindex.excl alias
        plg.callbacks.del(alias)

feudPluginLoad:
  var
    aliases = plg.getAliases()

  if aliases.atable.isNil:
    aliases.atable = newTable[string, string]()
  else:
    for alias in aliases.atable.keys():
      plg.setupAlias(alias)

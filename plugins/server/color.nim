import strutils

import "../../src"/pluginapi

proc doSet(plg: var Plugin, cmds: string) =
  for cmd in cmds.splitLines():
    plg.ctx.handleCommand(plg.ctx, "eMsg " & cmd.strip())

feudPluginDepends(["window"])

feudPluginLoad:
  # Font
  plg.doSet("""
    SCI_STYLESETFONT 0 Consolas
    SCI_STYLESETSIZE STYLE_DEFAULT 10
  """)

  # File type
  discard plg.ctx.msg(plg.ctx, SCI_SETLEXER, SCLEX_NIMROD)
  discard plg.ctx.msg(plg.ctx, SCI_SETKEYWORDS, 0, "addr and as asm block break case cast const continue converter discard div elif else end enum except exception finally for from generic if implies import in include is isnot iterator lambda macro method mod nil not notin object of or out proc ptr raise ref return shl shr template try tuple type var when where while with without xor yield".cstring)

  # Color
  plg.doSet("""
    SCI_STYLESETFORE SCE_P_IDENTIFIER 0xff00ff
    SCI_STYLESETFORE SCE_P_NUMBER 0x00ff00
    SCI_STYLESETFORE SCE_P_WORD 0xff0000
  """)

feudPluginUnload:
  discard plg.ctx.msg(plg.ctx, SCI_STYLERESETDEFAULT)
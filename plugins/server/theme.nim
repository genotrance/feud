import strformat, strutils, tables

import "../../src"/pluginapi

proc toRgb(bgr: string): string =
  return bgr[0 .. 1] & bgr[6 .. 7] & bgr[4 .. 5] & bgr[2 .. 3]

const
  gTheme = {
    "DEFAULT": "0xDDDDDD",

    "WORD": "0xF92672",

    "COMMENT": "0x75715E",
    "COMMENTLINE": "0x75715E",

    "COMMENTDOC": "0x75715E",
    "COMMENTLINEDOC": "0x75715E",

    "NUMBER": "0xAE81FF",
    "CHARACTER": "0xFD971F",

    "STRING": "0xE6DB74",
    "TRIPLE": "0xE6DB74",
    "TRIPLEDOUBLE": "0xE6DB74",

    "STRINGEOL": "0xFF0000",
    "NUMERROR": "0xFF0000",

    "OPERATOR": "0x66D9EF",
    "IDENTIFIER": "0xFFFFFF",
    "FUNCNAME": "0xFFFFFF"
  }.toTable()

  gBold = @["COMMENTDOC", "COMMENTLINEDOC", "OPERATOR"]

  gFore = "0xABB2BF".toRgb().parseHexInt()
  gBack = "0x282C34".toRgb().parseHexInt()
  gIndent = "0x686C74".toRgb().parseHexInt()

proc doSet(plg: var Plugin, cmds: string) =
  for cmd in cmds.splitLines():
    let
      cmd = cmd.strip()
    if cmd.len != 0:
      discard plg.ctx.handleCommand(plg.ctx, "eMsg " & cmd)

template doSet(msgID, wp, lp) =
  discard plg.ctx.msg(plg.ctx, msgID, wp, lp.toPtr)

template doSet(msgID, wp, lp, popup) =
  discard plg.ctx.msg(plg.ctx, msgID, wp, lp.toPtr, popup)

proc setPopupTheme(plg: var Plugin) {.feudCallback.} =
  # Horizontal scroll
  doSet(SCI_SETSCROLLWIDTH, 1, 0, popup=true)
  doSet(SCI_SETSCROLLWIDTHTRACKING, 1, 0, popup=true)

  # No margins
  doSet(SCI_SETMARGINWIDTHN, 1, 0, popup=true)

  # Font
  discard plg.ctx.msg(plg.ctx, SCI_STYLESETFONT, STYLE_DEFAULT, "Consolas".cstring, popup=true)
  doSet(SCI_STYLESETSIZE, STYLE_DEFAULT, 12, popup=true)

  # Basic colors
  doSet(SCI_STYLESETFORE, 0, gBack, popup=true)
  doSet(SCI_STYLESETBACK, 0, gFore, popup=true)
  doSet(SCI_STYLESETFORE, STYLE_DEFAULT, gBack, popup=true)
  doSet(SCI_STYLESETBACK, STYLE_DEFAULT, gFore, popup=true)
  doSet(SCI_SETCARETFORE, 0xFFFFFF, 0, popup=true)

proc setTheme(plg: var Plugin) {.feudCallback.} =
  let
    lexer =
      if plg.ctx.cmdParam.len != 0:
        plg.ctx.cmdParam[0].toUpperAscii
      else:
        ""

  # Font
  discard plg.ctx.msg(plg.ctx, SCI_STYLESETFONT, STYLE_DEFAULT, "Consolas".cstring)
  doSet(SCI_STYLESETSIZE, STYLE_DEFAULT, 10)

  # Basic colors
  doSet(SCI_STYLESETFORE, 0, gFore)
  doSet(SCI_STYLESETBACK, 0, gBack)
  doSet(SCI_STYLESETFORE, STYLE_DEFAULT, gFore)
  doSet(SCI_STYLESETBACK, STYLE_DEFAULT, gBack)
  doSet(SCI_SETCARETFORE, 0xFFFFFF, 0)

  # Line numbers
  doSet(SCI_SETMARGINTYPEN, 0, 1)
  doSet(SCI_SETMARGINWIDTHN, 0, 32)
  doSet(SCI_STYLESETFORE, STYLE_LINENUMBER, gFore)
  doSet(SCI_STYLESETBACK, STYLE_LINENUMBER, gBack)

  # Horizontal scroll
  doSet(SCI_SETSCROLLWIDTH, 1, 0)
  doSet(SCI_SETSCROLLWIDTHTRACKING, 1, 0)

  doSet(SCI_STYLESETBACK, STYLE_INDENTGUIDE, gIndent)

  if lexer.len != 0:
    let
      prefix = &"SCE_{lexer}_"

    for i in gTheme.keys:
      let
        key = prefix & i
      if SciDefs.hasKey(key):
        plg.doSet(&"""
          SCI_STYLESETFORE {key} {gTheme[i].toRgb()}
          SCI_STYLESETBACK {key} {gBack}
        """)

        if i in gBold:
          plg.doSet(&"SCI_STYLESETBOLD {key} 1")

feudPluginDepends(["config"])

feudPluginLoad:
  discard plg.ctx.handleCommand(plg.ctx, "hook postNewWindow setPopupTheme")
  discard plg.ctx.handleCommand(plg.ctx, "hook postNewWindow setTheme")

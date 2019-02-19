import strformat, strutils, tables

import "../../src"/pluginapi

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

    "STRINGEOL": "0x0000FF",
    "NUMERROR": "0x0000FF",

    "OPERATOR": "0x66D9EF",
    "IDENTIFIER": "0xFFFFFF",
    "FUNCNAME": "0xFFFFFF"
  }.toTable()

  gBold = @["COMMENTDOC", "COMMENTLINEDOC", "OPERATOR"]

proc toRgb(bgr: string): string =
  return bgr[0 .. 1] & bgr[6 .. 7] & bgr[4 .. 5] & bgr[2 .. 3]

proc doSet(plg: var Plugin, cmds: string) =
  for cmd in cmds.splitLines():
    plg.ctx.handleCommand(plg.ctx, "eMsg " & cmd.strip())

proc setTheme(plg: var Plugin) {.feudCallback.} =
  let
    lexer =
      if plg.ctx.cmdParam.len != 0:
        plg.ctx.cmdParam[0].toUpperAscii
      else:
        ""

    fore = "0xABB2BF".toRgb()
    back = "0x282C34".toRgb()

  # Font
  plg.doSet("""
    SCI_STYLESETFONT STYLE_DEFAULT Consolas
    SCI_STYLESETSIZE STYLE_DEFAULT 10
  """)

  # Basic colors
  plg.doSet(&"""
    SCI_STYLESETFORE STYLE_DEFAULT {fore}
    SCI_STYLESETBACK STYLE_DEFAULT {back}
    SCI_SETCARETFORE 0xFFFFFF
  """)

  # Line numbers
  plg.doSet(&"""
    SCI_SETMARGINTYPEN 0 1
    SCI_SETMARGINWIDTHN 0 32
    SCI_STYLESETFORE STYLE_LINENUMBER {fore}
    SCI_STYLESETBACK STYLE_LINENUMBER {back}
  """)

  if lexer.len != 0:
    let
      prefix = &"SCE_{lexer}_"

    for i in gTheme.keys:
      let
        key = prefix & i
      if SciDefs.hasKey(key):
        plg.doSet(&"""
          SCI_STYLESETFORE {key} {gTheme[i].toRgb()}
          SCI_STYLESETBACK {key} {back}
        """)

        if i in gBold:
          plg.doSet(&"SCI_STYLESETBOLD {key} 1")

feudPluginDepends(["window"])

feudPluginLoad:
  plg.setTheme()

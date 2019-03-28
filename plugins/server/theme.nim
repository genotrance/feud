import strformat, strutils, tables

import "../../src"/pluginapi

proc toBgr(rgb: string): int =
  if rgb.len != 0 and rgb[0 .. 1] == "0x":
    let
      bgr = rgb[0 .. 1] & rgb[6 .. 7] & rgb[4 .. 5] & rgb[2 .. 3]

    try:
      result = parseHexInt(bgr)
    except:
      discard

const
  gBold = @["COMMENTDOC", "COMMENTLINEDOC", "OPERATOR"]

proc get(plg: var Plugin, name: string): string =
  if plg.ctx.handleCommand(plg.ctx, &"get theme:{name}"):
    if plg.ctx.cmdParam.len != 0 and plg.ctx.cmdParam[0].len != 0:
      return plg.ctx.cmdParam[0]

proc getInt(plg: var Plugin, name: string): int =
  let
    str = plg.get(name)

  try:
    result = parseInt(str)
  except:
    discard

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
  let
    fontName = plg.get("fontName")
    fontSize = plg.getInt("fontSize")

    fgColor = plg.get("fgColor").toBgr()
    bgColor = plg.get("bgColor").toBgr()
    indentColor = plg.get("indentColor").toBgr()
    caretColor = plg.get("caretColor").toBgr()

  # Horizontal scroll
  doSet(SCI_SETSCROLLWIDTH, 1, 0, popup=true)
  doSet(SCI_SETSCROLLWIDTHTRACKING, 1, 0, popup=true)

  # No margins
  doSet(SCI_SETMARGINWIDTHN, 1, 0, popup=true)

  # Font
  if fontName.len != 0:
    discard plg.ctx.msg(plg.ctx, SCI_STYLESETFONT, STYLE_DEFAULT, fontName.cstring, popup=true)

  if fontSize > 0:
    doSet(SCI_STYLESETSIZE, STYLE_DEFAULT, fontSize, popup=true)

  # Basic colors
  if bgColor != 0:
    doSet(SCI_STYLESETFORE, 0, bgColor, popup=true)
    doSet(SCI_STYLESETFORE, STYLE_DEFAULT, bgColor, popup=true)

  if fgColor != 0:
    doSet(SCI_STYLESETBACK, 0, fgColor, popup=true)
    doSet(SCI_STYLESETBACK, STYLE_DEFAULT, fgColor, popup=true)

  if indentColor != 0:
    doSet(SCI_SETCARETFORE, caretColor, 0, popup=true)

proc setTheme(plg: var Plugin) {.feudCallback.} =
  let
    lexer =
      if plg.ctx.cmdParam.len != 0:
        plg.ctx.cmdParam[0].toUpperAscii
      else:
        ""

    fontName = plg.get("fontName")
    fontSize = plg.getInt("fontSize")

    fgColor = plg.get("fgColor").toBgr()
    bgColor = plg.get("bgColor").toBgr()
    indentColor = plg.get("indentColor").toBgr()
    caretColor = plg.get("caretColor").toBgr()

    lineNumbers = plg.get("lineNumbers")
    lineNumberWidth = plg.getInt("lineNumberWidth")

  # Font
  if fontName.len != 0:
    discard plg.ctx.msg(plg.ctx, SCI_STYLESETFONT, STYLE_DEFAULT, fontName.cstring)

  if fontSize > 0:
    doSet(SCI_STYLESETSIZE, STYLE_DEFAULT, fontSize)

  # Basic colors
  if fgColor != 0:
    doSet(SCI_STYLESETFORE, 0, fgColor)
    doSet(SCI_STYLESETFORE, STYLE_DEFAULT, fgColor)

  if bgColor != 0:
    doSet(SCI_STYLESETBACK, 0, bgColor)
    doSet(SCI_STYLESETBACK, STYLE_DEFAULT, bgColor)

  if caretColor != 0:
    doSet(SCI_SETCARETFORE, caretColor, 0)

  if indentColor != 0:
    doSet(SCI_STYLESETBACK, STYLE_INDENTGUIDE, indentColor)

  # Line numbers
  if lineNumbers == "true":
    doSet(SCI_SETMARGINTYPEN, 0, 1)

    if lineNumberWidth > 0:
      doSet(SCI_SETMARGINWIDTHN, 0, lineNumberWidth)

    if fgColor != 0:
      doSet(SCI_STYLESETFORE, STYLE_LINENUMBER, fgColor)

    if bgColor != 0:
      doSet(SCI_STYLESETBACK, STYLE_LINENUMBER, bgColor)

  # Horizontal scroll
  doSet(SCI_SETSCROLLWIDTH, 1, 0)
  doSet(SCI_SETSCROLLWIDTHTRACKING, 1, 0)

  var
    theme = {
      "DEFAULT": plg.get("defColor"),

      "WORD": plg.get("wordColor"),

      "COMMENT": plg.get("commentColor"),
      "COMMENTLINE": plg.get("commentColor"),

      "COMMENTDOC": plg.get("docColor"),
      "COMMENTLINEDOC": plg.get("docColor"),

      "NUMBER": plg.get("numberColor"),
      "CHARACTER": plg.get("charColor"),

      "STRING": plg.get("stringColor"),
      "TRIPLE": plg.get("stringColor"),
      "TRIPLEDOUBLE": plg.get("stringColor"),

      "STRINGEOL": plg.get("errorColor"),
      "NUMERROR": plg.get("errorColor"),

      "OPERATOR": plg.get("opColor"),
      "IDENTIFIER": plg.get("idColor"),

      "FUNCNAME": plg.get("idColor")
    }.toTable()

  if lexer.len != 0:
    let
      prefix = &"SCE_{lexer}_"

    for i in theme.keys:
      let
        key = prefix & i
      if SciDefs.hasKey(key) and theme[i].len != 0:
        plg.doSet(&"""
          SCI_STYLESETFORE {key} {theme[i].toBgr()}
          SCI_STYLESETBACK {key} {bgColor}
        """)

        if i in gBold:
          plg.doSet(&"SCI_STYLESETBOLD {key} 1")

feudPluginDepends(["config"])

feudPluginLoad:
  discard plg.ctx.handleCommand(plg.ctx, "hook postNewWindow setPopupTheme")
  discard plg.ctx.handleCommand(plg.ctx, "hook postNewWindow setTheme")

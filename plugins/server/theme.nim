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
    fontName = plg.getCbResult("get theme:fontName")
    fontSize = plg.getCbIntResult("get theme:fontSize")

    fgColor = plg.getCbResult("get theme:fgColor").toBgr()
    bgColor = plg.getCbResult("get theme:bgColor").toBgr()
    indentColor = plg.getCbResult("get theme:indentColor").toBgr()
    caretColor = plg.getCbResult("get theme:caretColor").toBgr()

  # Horizontal scroll
  doSet(SCI_SETHSCROLLBAR, 0, 0, popup=true)

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

    fontName = plg.getCbResult("get theme:fontName")
    fontSize = plg.getCbIntResult("get theme:fontSize")

    fgColor = plg.getCbResult("get theme:fgColor").toBgr()
    bgColor = plg.getCbResult("get theme:bgColor").toBgr()
    indentColor = plg.getCbResult("get theme:indentColor").toBgr()
    caretColor = plg.getCbResult("get theme:caretColor").toBgr()

    lineNumbers = plg.getCbResult("get theme:lineNumbers")
    lineNumberWidth = plg.getCbIntResult("get theme:lineNumberWidth")

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
      "DEFAULT": plg.getCbResult("get theme:defColor"),

      "WORD": plg.getCbResult("get theme:wordColor"),
      "WORD2": plg.getCbResult("get theme:wordColor"),

      "COMMENT": plg.getCbResult("get theme:commentColor"),
      "COMMENTLINE": plg.getCbResult("get theme:commentColor"),

      "COMMENTDOC": plg.getCbResult("get theme:docColor"),
      "COMMENTLINEDOC": plg.getCbResult("get theme:docColor"),

      "NUMBER": plg.getCbResult("get theme:numberColor"),
      "CHARACTER": plg.getCbResult("get theme:charColor"),

      "STRING": plg.getCbResult("get theme:stringColor"),
      "TRIPLE": plg.getCbResult("get theme:stringColor"),
      "TRIPLEDOUBLE": plg.getCbResult("get theme:stringColor"),

      "STRINGEOL": plg.getCbResult("get theme:errorColor"),
      "NUMERROR": plg.getCbResult("get theme:errorColor"),

      "OPERATOR": plg.getCbResult("get theme:opColor"),
      "IDENTIFIER": plg.getCbResult("get theme:idColor"),
      "PREPROCESSOR": plg.getCbResult("get theme:preprocColor"),

      "FUNCNAME": plg.getCbResult("get theme:idColor")
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

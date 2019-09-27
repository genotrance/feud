import os, strformat, strutils, tables

import xml

import "../../src"/pluginapi

const
  lexMap = {
    "autoit": SCLEX_AU3,
    "c": SCLEX_CPP,
    "cs": SCLEX_CPP,
    "inno": SCLEX_INNOSETUP,
    "java": SCLEX_CPP,
    "javascript.js": SCLEX_CPP,
    "objc": SCLEX_CPP,
    "php": SCLEX_PHPSCRIPT,
    "postscript": SCLEX_PS,
    "swift": SCLEX_CPP,
  }.toTable()

  lexName = {
    "autoit": "au3",
    "cpp": "c",
    "cs": "c",
    "java": "c",
    "javascript.js": "c",
    "objc": "c",
    "php": "hphp",
    "postscript": "ps",
    "python": "p",
    "swift": "c",
  }.toTable()

type
  Lang = object
    name: string
    ext: seq[string]
    commentLine: string
    keywords: seq[string]

const
  gLangs = (block:
    var
      ltable = initTable[string, Lang](initialsize = 256)
      langfile = currentSourcePath.parentDir()/"langs.model.xml"

    doAssert langfile.fileExists(), "Failed to find " & langfile

    var
      langdata = langfile.staticRead()
      x = langdata.parseXml()

    for ls in x.children:
      for l in ls.children:
        var
          lang: Lang
        lang.name = l.attr("name")
        if lang.name.len != 0:
          lang.ext = l.attr("ext").split(' ')
          lang.commentLine = l.attr("commentLine")

          for kw in l.children:
            lang.keywords.add kw.text

          for ext in lang.ext:
            ltable[ext] = lang

    ltable
  )

proc getLangLexer(lang: Lang): int =
  let
    lexerName = "SCLEX_" & lang.name.toUpperAscii
  if SciDefs.hasKey(lexerName):
    result = SciDefs[lexerName]
  elif lexMap.hasKey(lang.name):
    result = lexMap[lang.name]

proc getLangLexerName(lang: Lang): string =
  if lexName.hasKey(lang.name):
    result = lexName[lang.name]
  else:
    result = lang.name

proc getLang(plg: var Plugin, cmd: var CmdData): Lang =
  if cmd.params.len != 0:
    var
      (_, _, ext) = cmd.params[0].splitFile()

    ext = ext.strip(chars={'.'})

    if gLangs.hasKey(ext):
      result = gLangs[ext]

proc getCommentLine(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    lang = plg.getLang(cmd)

  if not lang.name.len != 0 and lang.commentLine.len != 0:
    cmd.returned.add lang.commentLine

proc getLexer(plg: var Plugin): int =
  result = plg.ctx.msg(plg.ctx, SCI_GETLEXER)

proc resetLexer(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  discard plg.ctx.msg(plg.ctx, SCI_SETLEXER, SCLEX_NULL)
  for i in 0 .. 8:
    discard plg.ctx.msg(plg.ctx, SCI_SETKEYWORDS, i, "".cstring)

proc setLexer(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    lang = plg.getLang(cmd)

  if not lang.name.len != 0:
    if lang.getLangLexer() != plg.getLexer():
      plg.ctx.notify(plg.ctx, &"Set language to {lang.name} for '{cmd.params[0].extractFilename()}'")

    plg.resetLexer(cmd)
    discard plg.ctx.msg(plg.ctx, SCI_SETLEXER, lang.getLangLexer())
    for i in 0 .. lang.keywords.len-1:
      discard plg.ctx.msg(plg.ctx, SCI_SETKEYWORDS, i, lang.keywords[i].cstring)

    cmd.returned.add lang.getLangLexerName()
  else:
    plg.resetLexer(cmd)
  
feudPluginDepends(["window"])

feudPluginLoad()

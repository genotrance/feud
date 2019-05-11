import os, parsexml, sequtils, streams, strformat, strutils, tables, xmltree

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
  Lang = ref object
    name: string
    lexer: int
    lexName: string
    ext: seq[string]
    commentLine: string
    keywords: seq[string]

var
  gLangs = newTable[string, Lang]()

proc addLang(plg: var Plugin, lang: Lang) =
  for ext in lang.ext:
    gLangs[ext] = lang

proc initLangs(plg: var Plugin) =
  var
    lang: Lang

    langfile = getAppDir()/"plugins"/"server"/"langs.model.xml"

  if not langfile.fileExists():
    echo "Failed to find " & langfile
    return

  var
    langstream = langfile.newFileStream(fmRead)
    x: XmlParser

  x.open(langstream, langfile)

  while true:
    x.next()
    case x.kind
    of xmlElementOpen:
      if x.elementName == "Language":
        if not lang.isNil and lang.ext.len != 0 and lang.lexer != 0:
          plg.addLang(lang)
        lang = new(Lang)
        x.next()
        while x.kind == xmlAttribute:
          if x.attrKey == "name":
            lang.name = x.attrValue
            let
              lexerName = "SCLEX_" & lang.name.toUpperAscii
            if SciDefs.hasKey(lexerName):
              lang.lexer = SciDefs[lexerName]
            elif lexMap.hasKey(lang.name):
              lang.lexer = lexMap[lang.name]
            if lexName.hasKey(lang.name):
              lang.lexName = lexName[lang.name]
            else:
              lang.lexName = lang.name
          elif x.attrValue.len != 0:
            case x.attrKey
            of "ext":
              lang.ext = x.attrValue.split(' ')
            of "commentLine":
              lang.commentLine = x.attrValue
          x.next()
    of xmlCharData:
      lang.keywords.add x.charData
    of xmlEof:
      break
    else:
      discard

  x.close()

proc getLang(plg: var Plugin): Lang =
  if plg.ctx.cmdParam.len != 0:
    var
      (_, _, ext) = plg.ctx.cmdParam[0].splitFile()

    ext = ext.strip(chars={'.'})

    if gLangs.hasKey(ext):
      result = gLangs[ext]

proc getCommentLine(plg: var Plugin) {.feudCallback.} =
  var
    lang = plg.getLang()

  if not lang.isNil and lang.commentLine.len != 0:
    plg.ctx.cmdParam = @[lang.commentLine]
  else:
    plg.ctx.cmdParam = @[]

proc getLexer(plg: var Plugin): int =
  result = plg.ctx.msg(plg.ctx, SCI_GETLEXER)

proc resetLexer(plg: var Plugin) {.feudCallback.} =
  discard plg.ctx.msg(plg.ctx, SCI_SETLEXER, SCLEX_NULL)
  for i in 0 .. 8:
    discard plg.ctx.msg(plg.ctx, SCI_SETKEYWORDS, i, "".cstring)

proc setLexer(plg: var Plugin) {.feudCallback.} =
  var
    lang = plg.getLang()

  if not lang.isNil:
    if lang.lexer != plg.getLexer():
      plg.ctx.notify(plg.ctx, &"Set language to {lang.name} for '{plg.ctx.cmdParam[0].extractFilename()}'")

    plg.resetLexer()
    discard plg.ctx.msg(plg.ctx, SCI_SETLEXER, lang.lexer)
    for i in 0 .. lang.keywords.len-1:
      discard plg.ctx.msg(plg.ctx, SCI_SETKEYWORDS, i, lang.keywords[i].cstring)

    plg.ctx.cmdParam = @[lang.lexName]
  else:
    plg.resetLexer()
    plg.ctx.cmdParam = @[]
  
feudPluginDepends(["window"])

feudPluginLoad:
  plg.initLangs()

if isMainModule:
  var
    plg = new(Plugin)

  plg.initLangs()
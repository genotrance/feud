import os, parsexml, sequtils, streams, strutils, tables, xmltree

import "../../src"/pluginapi

type
  Lang = ref object
    name: string
    lexer: int
    ext: seq[string]
    keywords: seq[string]

var
  gLangs = newTable[string, Lang]()

proc addLang(plg: var Plugin, lang: Lang) =
  for ext in lang.ext:
    gLangs[ext] = lang

proc initLangs(plg: var Plugin) =
  var
    lang: Lang

    langfile = currentSourcePath.parentDir()/"langs.model.xml"
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
          elif x.attrKey == "ext" and x.attrValue.len != 0:
            lang.ext = x.attrValue.split(' ')
          x.next()
    of xmlCharData:
      lang.keywords.add x.charData
    of xmlEof:
      break
    else:
      discard

  x.close()

proc resetLexer(plg: var Plugin) {.feudCallback.} =
  discard plg.ctx.msg(plg.ctx, SCI_SETLEXER, SCLEX_NULL)
  for i in 0 .. 8:
    discard plg.ctx.msg(plg.ctx, SCI_SETKEYWORDS, i, "".cstring)

proc setLexer(plg: var Plugin) {.feudCallback.} =
  plg.resetLexer()

  if plg.ctx.cmdParam.len != 0:
    var
      (_, _, ext) = plg.ctx.cmdParam[0].splitFile()

    ext = ext.strip(chars={'.'})

    if gLangs.hasKey(ext):
      var
        lang = gLangs[ext]

      discard plg.ctx.msg(plg.ctx, SCI_SETLEXER, lang.lexer)
      for i in 0 .. lang.keywords.len-1:
        discard plg.ctx.msg(plg.ctx, SCI_SETKEYWORDS, i, lang.keywords[i].cstring)

      plg.ctx.cmdParam = @[lang.name]
    else:
      plg.ctx.cmdParam = @[]

feudPluginDepends(["window"])

feudPluginLoad:
  plg.initLangs()

if isMainModule:
  var
    plg = new(Plugin)

  plg.initLangs()
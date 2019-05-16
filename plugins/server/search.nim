import os, strformat, strutils

import "../.."/src/pluginapi

type
  Search = ref object
    needle: string
    matchcase: bool
    wholeword: bool
    posix: bool
    regex: bool
    cppregex: bool
    found: bool

proc unhighlight(plg: var Plugin) {.feudCallback.} =
  var
    search = getCtxData[Search](plg)
    length = plg.ctx.msg(plg.ctx, SCI_GETLENGTH)
  discard plg.ctx.msg(plg.ctx, SCI_SETINDICATORVALUE, 0)
  discard plg.ctx.msg(plg.ctx, SCI_INDICATORCLEARRANGE, 0, length.toPtr)
  search.found = false

proc search(plg: var Plugin) {.feudCallback.} =
  var
    search = getCtxData[Search](plg)
    reverse = false
    tpos = false
    found = search.found

  if plg.ctx.cmdParam.len != 0:
    var
      params = plg.ctx.cmdParam[0].strip().parseCmdLine()

    if "-r" in params:
      reverse = true
      params.delete(params.find("-r"))

    if params.len != 0:
      freeCtxData[Search](plg)
      search = getCtxData[Search](plg)

      for param in params:
        let
          param = param.strip()
        case param:
          of "-c":
            search.matchcase = true
          of "-w":
            search.wholeword = true
          of "-p":
            search.posix = true
          of "-t":
            tpos = true
          of "-x":
            search.regex = true
          of "-X":
            search.regex = true
            search.cppregex = true
          else:
            if search.needle.len == 0:
              search.needle = param
            else:
              search.needle &= " " & param

  if search.needle.len == 0:
    search.needle = plg.getSelection()

  if search.needle.len != 0:
    plg.unhighlight()

    let
      curpos = plg.ctx.msg(plg.ctx, SCI_GETCURRENTPOS)
      curstart = plg.ctx.msg(plg.ctx, SCI_GETTARGETSTART)
      curend = plg.ctx.msg(plg.ctx, SCI_GETTARGETEND)

    if not tpos:
      if not reverse:
        discard plg.ctx.msg(plg.ctx, SCI_TARGETWHOLEDOCUMENT)
        discard plg.ctx.msg(plg.ctx, SCI_SETTARGETSTART, curpos)
      else:
        discard plg.ctx.msg(plg.ctx, SCI_SETTARGETSTART, curpos)
        discard plg.ctx.msg(plg.ctx, SCI_SETTARGETEND, 0)

    var
      flags = 0
    if search.matchcase:
      flags = flags or SCFIND_MATCHCASE
    if search.wholeword:
      flags = flags or SCFIND_WHOLEWORD
    if search.posix:
      flags = flags or SCFIND_POSIX
    if search.regex:
      flags = flags or SCFIND_REGEXP
    if search.cppregex:
      flags = flags or SCFIND_CXX11REGEX
    if flags != 0:
      discard plg.ctx.msg(plg.ctx, SCI_SETSEARCHFLAGS, flags)

    var
      pos = plg.ctx.msg(plg.ctx, SCI_SEARCHINTARGET, search.needle.len, search.needle.cstring)
    if pos == curpos and not reverse and found and pos == curstart and pos+search.needle.len == curend:
      discard plg.ctx.msg(plg.ctx, SCI_TARGETWHOLEDOCUMENT)
      discard plg.ctx.msg(plg.ctx, SCI_SETTARGETSTART, curpos+1)
      pos = plg.ctx.msg(plg.ctx, SCI_SEARCHINTARGET, search.needle.len, search.needle.cstring)

    if pos != -1:
      discard plg.ctx.msg(plg.ctx, SCI_GOTOPOS, pos)
      discard plg.ctx.handleCommand(plg.ctx, "runHook preSearchHighlight")
      discard plg.ctx.msg(plg.ctx, SCI_SETINDICATORVALUE, 0)
      discard plg.ctx.msg(plg.ctx, SCI_INDICATORFILLRANGE, pos, search.needle.len.toPtr)
      search.found = true
  else:
    discard plg.ctx.handleCommand(plg.ctx, "togglePopup search")

proc highlight(plg: var Plugin) {.feudCallback.} =
  let
    search = plg.getSelection()
    length = search.len

  plg.unhighlight()
  if length != 0:
    freeCtxData[Search](plg)
    getCtxData[Search](plg).needle = search

    var
      matches: seq[int]
      pos = 0
    while pos != -1:
      discard plg.ctx.msg(plg.ctx, SCI_TARGETWHOLEDOCUMENT)
      discard plg.ctx.msg(plg.ctx, SCI_SETSEARCHFLAGS, SCFIND_MATCHCASE)
      discard plg.ctx.msg(plg.ctx, SCI_SETTARGETSTART, pos)
      pos = plg.ctx.msg(plg.ctx, SCI_SEARCHINTARGET, search.len, search.cstring)
      if pos != -1:
        matches.add pos
        pos += 1

    if matches.len != 0:
      discard plg.ctx.handleCommand(plg.ctx, "runHook preSearchHighlight")
      discard plg.ctx.msg(plg.ctx, SCI_SETINDICATORVALUE, 0)
      for match in matches:
        discard plg.ctx.msg(plg.ctx, SCI_INDICATORFILLRANGE, match, length.toPtr)

proc replace(plg: var Plugin) {.feudCallback.} =
  if plg.ctx.cmdParam.len != 0:
    var
      params = plg.ctx.cmdParam[0].strip().parseCmdLine()
      sparams: seq[string]
      srch: string
      repl: string
      all = false
      data: cstring

    for param in params:
      if param.len != 0:
        if param[0] != '-' and srch.len != 0:
          repl = param
        elif param == "-a":
          all = true
        else:
          sparams.add param
          if param[0] != '-':
            srch = param

    if sparams.len != 0 and repl.len != 0:
      var
        tlast = -1
        count = 0
      discard plg.ctx.msg(plg.ctx, SCI_BEGINUNDOACTION)
      defer:
        discard plg.ctx.msg(plg.ctx, SCI_ENDUNDOACTION)
      while true:
        plg.ctx.cmdParam = sparams
        if count != 0:
          plg.ctx.cmdParam.add "-t"

        plg.search()

        let
          tstart = plg.ctx.msg(plg.ctx, SCI_GETTARGETSTART)
          tend = plg.ctx.msg(plg.ctx, SCI_GETTARGETEND)
        if tstart < tend and tstart != tlast:
          discard plg.ctx.msg(plg.ctx, SCI_REPLACETARGET, repl.len, repl.cstring)
          tlast = tstart
          count += 1
        else:
          break

        if not all:
          break

        discard plg.ctx.msg(plg.ctx, SCI_TARGETWHOLEDOCUMENT)
        discard plg.ctx.msg(plg.ctx, SCI_SETTARGETSTART, tend)

      if count != 0:
        plg.ctx.notify(plg.ctx, &"Replaced {$count} instances of '{srch}' with '{repl}'")

feudPluginDepends(["config"])

feudPluginLoad:
  discard plg.ctx.handleCommand(plg.ctx, "hook onWindowSelection highlight")
import strformat, strutils

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

proc unhighlight(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    search = getCtxData[Search](plg)
    length = plg.ctx.msg(plg.ctx, SCI_GETLENGTH)
  discard plg.ctx.msg(plg.ctx, SCI_SETINDICATORVALUE, 0)
  discard plg.ctx.msg(plg.ctx, SCI_INDICATORCLEARRANGE, 0, length.toPtr)
  search.found = false

proc search(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    search = getCtxData[Search](plg)
    reverse = false
    tpos = false
    found = search.found
    ccmd: CmdData

  if cmd.params.len != 0:
    if "-r" in cmd.params:
      reverse = true
      cmd.params.delete(cmd.params.find("-r"))

    if cmd.params.len != 0:
      freeCtxData[Search](plg)
      search = getCtxData[Search](plg)

      for param in cmd.params:
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
    plg.unhighlight(cmd)

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
      ccmd = newCmdData("runHook preSearchHighlight")
      plg.ctx.handleCommand(plg.ctx, ccmd)
      discard plg.ctx.msg(plg.ctx, SCI_SETINDICATORVALUE, 0)
      discard plg.ctx.msg(plg.ctx, SCI_INDICATORFILLRANGE, pos, search.needle.len.toPtr)
      search.found = true
  else:
    ccmd = newCmdData("togglePopup search")
    plg.ctx.handleCommand(plg.ctx, ccmd)

proc highlight(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  let
    search = plg.getSelection()
    length = search.len

  plg.unhighlight(cmd)
  if length != 0:
    freeCtxData[Search](plg)
    getCtxData[Search](plg).needle = search

    var
      matches: seq[int]
      pos = 0
      ccmd: CmdData
    while pos != -1:
      discard plg.ctx.msg(plg.ctx, SCI_TARGETWHOLEDOCUMENT)
      discard plg.ctx.msg(plg.ctx, SCI_SETSEARCHFLAGS, SCFIND_MATCHCASE)
      discard plg.ctx.msg(plg.ctx, SCI_SETTARGETSTART, pos)
      pos = plg.ctx.msg(plg.ctx, SCI_SEARCHINTARGET, search.len, search.cstring)
      if pos != -1:
        matches.add pos
        pos += 1

    if matches.len != 0:
      ccmd = newCmdData("runHook preSearchHighlight")
      plg.ctx.handleCommand(plg.ctx, ccmd)
      discard plg.ctx.msg(plg.ctx, SCI_SETINDICATORVALUE, 0)
      for match in matches:
        discard plg.ctx.msg(plg.ctx, SCI_INDICATORFILLRANGE, match, length.toPtr)

proc replace(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  if cmd.params.len != 0:
    var
      sparams: seq[string]
      srch: string
      repl: string
      all = false
      ccmd: CmdData

    for param in cmd.params:
      if param.len != 0:
        if param[0] != '-' and srch.len != 0:
          repl = param
        elif param == "-a":
          all = true
        else:
          sparams.add param
          if param[0] != '-':
            srch = param

    echo srch
    echo repl
    if sparams.len != 0 and repl.len != 0:
      var
        tlast = -1
        count = 0
      discard plg.ctx.msg(plg.ctx, SCI_BEGINUNDOACTION)
      defer:
        discard plg.ctx.msg(plg.ctx, SCI_ENDUNDOACTION)
      while true:
        ccmd = new(CmdData)
        ccmd.params = sparams
        if count != 0:
          ccmd.params.add "-t"

        plg.search(ccmd)

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
  var
    ccmd = newCmdData("hook onWindowSelection highlight")
  plg.ctx.handleCommand(plg.ctx, ccmd)
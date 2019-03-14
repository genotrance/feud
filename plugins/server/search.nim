import os, strutils

import "../.."/src/pluginapi

type
  Search = ref object
    needle: string
    reverse: bool
    matchcase: bool
    wholeword: bool
    posix: bool
    regex: bool
    cppregex: bool

proc search(plg: var Plugin) {.feudCallback.} =
  var
    search = getCtxData[Search](plg)

  if plg.ctx.cmdParam.len != 0:
    let
      params = plg.ctx.cmdParam[0].strip().parseCmdLine()
    if params.len != 0:
      freeCtxData[Search](plg)
      search = getCtxData[Search](plg)

      for param in params:
        let
          param = param.strip()
        case param:
          of "-r":
            search.reverse = true
          of "-c":
            search.matchcase = true
          of "-w":
            search.wholeword = true
          of "-p":
            search.posix = true
          of "-x":
            search.regex = true
          of "-X":
            search.cppregex = true
          else:
            if search.needle.len == 0:
              search.needle = param
            else:
              search.needle &= " " & param

  if search.needle.len == 0:
    let
      length = plg.ctx.msg(plg.ctx, SCI_GETSELTEXT, 0, nil)
    if length != 0:
      var
        data = alloc0(length+1)
      defer: data.dealloc()
      
      discard plg.ctx.msg(plg.ctx, SCI_GETSELTEXT, 0, data)
      search.needle = ($cast[cstring](data)).strip()

  if search.needle.len != 0:
    let
      curpos = plg.ctx.msg(plg.ctx, SCI_GETCURRENTPOS)
    discard plg.ctx.msg(plg.ctx, SCI_TARGETWHOLEDOCUMENT)
    if not search.reverse:
      discard plg.ctx.msg(plg.ctx, SCI_SETTARGETSTART, curpos)
    else:
      discard plg.ctx.msg(plg.ctx, SCI_SETTARGETEND, curpos)

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
    if pos == curpos and not search.reverse:
      discard plg.ctx.msg(plg.ctx, SCI_TARGETWHOLEDOCUMENT)
      discard plg.ctx.msg(plg.ctx, SCI_SETTARGETSTART, curpos+1)
      pos = plg.ctx.msg(plg.ctx, SCI_SEARCHINTARGET, search.needle.len, search.needle.cstring)
        
    if pos != -1:
      discard plg.ctx.msg(plg.ctx, SCI_GOTOPOS, pos)
  else:
    discard plg.ctx.handleCommand(plg.ctx, "togglePopup search")

feudPluginLoad()
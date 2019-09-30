import os, strformat, strutils

import "../.."/src/pluginapi

proc toggleComment(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  var
    selStart = plg.ctx.msg(plg.ctx, SCI_GETSELECTIONSTART)
    selEnd = plg.ctx.msg(plg.ctx, SCI_GETSELECTIONEND)
    selStartLine = plg.ctx.msg(plg.ctx, SCI_LINEFROMPOSITION, selStart)
    selEndLine = plg.ctx.msg(plg.ctx, SCI_LINEFROMPOSITION, selEnd)

  selStart = plg.ctx.msg(plg.ctx, SCI_POSITIONFROMLINE, selStartLine)
  if selEnd == 0:
    selEnd = plg.ctx.msg(plg.ctx, SCI_GETLINEENDPOSITION, selStartLine)
  else:
    let
      selEndLineStart = plg.ctx.msg(plg.ctx, SCI_POSITIONFROMLINE, selEndLine)
    if selEnd == selEndLineStart:
      selEndLine -= 1
    selEnd = plg.ctx.msg(plg.ctx, SCI_GETLINEENDPOSITION, selEndLine)

  if selStart < selEnd:
    var
      length = selEnd - selStart
      data = alloc0(length+1)
      sel: seq[string]
    defer: data.dealloc()

    discard plg.ctx.msg(plg.ctx, SCI_SETTARGETRANGE, selStart, selEnd.toPtr)
    discard plg.ctx.msg(plg.ctx, SCI_GETTARGETTEXT, 0, data)
    sel = ($cast[cstring](data)).splitLines(keepEol = true)

    if sel.len != 0:
      let
        docPath = plg.getCbResult("getDocPath")

      if docPath.len != 0:
        let
          commentLine = plg.getCbResult(&"getCommentLine {docPath.quoteShell}")
          commentLen = commentLine.len

        if commentLen != 0:
          for i in 0 .. sel.len-1:
            if sel[i].startsWith(commentLine):
              sel[i] = sel[i][commentLen .. ^1]
            elif sel[i].strip().len != 0:
              sel[i] = commentLine & sel[i]

          let
            newSel = sel.join("")
          discard plg.ctx.msg(plg.ctx, SCI_REPLACETARGET, newSel.len, newSel.cstring)

feudPluginDepends(["config", "window"])

feudPluginLoad()

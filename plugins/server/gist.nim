import os, httpcore, httpclient, json, strformat, strutils, uri

import "../../src"/pluginapi

proc getProxy*(): Proxy =
  ## Returns ``nil`` if no proxy is specified.
  var url = ""
  try:
    if existsEnv("http_proxy"):
      url = getEnv("http_proxy")
    elif existsEnv("https_proxy"):
      url = getEnv("https_proxy")
  except ValueError:
    return nil

  if url.len > 0:
    var parsed = parseUri(url)
    if parsed.scheme.len == 0 or parsed.hostname.len == 0:
      parsed = parseUri("http://" & url)
    let auth =
      if parsed.username.len > 0: parsed.username & ":" & parsed.password
      else: ""
    return newProxy($parsed, auth)
  else:
    return nil

proc isUrl*(url: string): bool =
  result = false
  if "http://" == url.substr(0, 6) or "https://" == url.substr(0, 7):
    result = true

proc adjustUrl(url: string): string =
  var parsed = url.parseUri()
  if parsed.hostname == "gist.github.com":
    parsed.hostname = "gist.githubusercontent.com"
    if parsed.path.split("/").len() == 2:
      parsed.path = "/anonymous" & parsed.path
    parsed.path &= "/raw"
  elif "pastebin.com" in parsed.hostname:
    if "raw" notin parsed.path:
      parsed.path = "/raw" & parsed.path
  elif parsed.hostname == "play.nim-lang.org":
    parsed.hostname = "gist.githubusercontent.com"
    parsed.path = "/anonymous/" & parsed.query.split("=")[1] & "/raw"
    parsed.query = ""
  elif "dpaste.de" in parsed.hostname or "ghostbin.com" in parsed.hostname:
    if "raw" notin parsed.path:
      parsed.path &= "/raw"

  if parsed.hostname in ["github.com", "www.github.com"]:
    parsed.path = parsed.path.replace("/blob/", "/raw/")

  return $parsed

proc getGist(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    client = newHttpClient(proxy = getProxy())
    success = false

  for param in cmd.params:
    try:
      let r = client.get(param.adjustUrl())
      if r.code().is2xx():
        var
          ccmd = newCmdData("newDoc")
        plg.ctx.handleCommand(plg.ctx, ccmd)
        if not ccmd.failed:
          discard plg.ctx.msg(plg.ctx, SCI_ADDTEXT, r.body.len, r.body.cstring)
          ccmd = newCmdData(&"setTitle {param}")
          plg.ctx.handleCommand(plg.ctx, ccmd)
          success = true
    except OSError:
      discard

    cmd.failed = not success
    plg.ctx.notify(plg.ctx,
      if not success:
        &"Failed to load gist {param}"
      else:
        &"Loaded gist {param}"
    )

proc gist(plg: var Plugin, cmd: var CmdData) {.feudCallback.} =
  var
    client = newHttpClient(proxy = getProxy())
    url = "http://ix.io"
    path = plg.getCbResult("getDocPath")
    name =
      if path.len != 0:
        path.extractFilename()
      else:
        "test.txt"
    post = "name:1=" & name & "&f:1="
    success = false
    gistUrl = ""

  discard plg.ctx.msg(plg.ctx, SCI_SETREADONLY, 1.toPtr)
  defer:
    discard plg.ctx.msg(plg.ctx, SCI_SETREADONLY, 0.toPtr)

  let
    sel = plg.getSelection()
    data =
      if sel.len != 0:
        sel
      else:
        $cast[cstring](plg.ctx.msg(plg.ctx, SCI_GETCHARACTERPOINTER))

  try:
    let r = client.post(url, post & data)
    if r.code() == Http200:
      gistUrl = r.body.strip()
      success = true
  except OSError:
    discard

  if not success:
    plg.ctx.notify(plg.ctx, &"Failed to create gist")
  else:
    var
      ccmd: CmdData
    plg.ctx.notify(plg.ctx, &"Created gist {gistUrl}")
    ccmd = newCmdData(&"togglePopup {gistUrl}")
    plg.ctx.handleCommand(plg.ctx, ccmd)
    discard plg.ctx.msg(plg.ctx, SCI_SELECTALL, popup = true)
    discard plg.ctx.msg(plg.ctx, SCI_COPY, popup = true)
    ccmd = newCmdData(&"togglePopup")
    plg.ctx.handleCommand(plg.ctx, ccmd)

feudPluginLoad()
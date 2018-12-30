import os, osproc, streams, strutils, tables, threadpool

import "."/[actions, globals, scihelper]

proc newPtrChannel[T](): ptr Channel[T] =
  result = cast[ptr Channel[T]](allocShared0(sizeof(Channel[T])))
  result[].open()

proc close[T](sch: var ptr Channel[T]) =
  sch[].close()
  deallocShared(sch)
  sch = nil

proc startPlugin(path: string, sch: ptr Channel[seq[string]]) {.thread.} =
  var
    p = startProcess("nim", args=["e", "--verbosity:0", path], options={poEchoCmd, poUsePath, poStdErrToStdOut})
    toP = p.inputStream()
    fromP = p.outputStream()

  while p.running():
    var
      lines: seq[string]
    while p.hasData():
      lines.add(fromP.readLine())

    if lines.len != 0:
      echo sch[].trySend(lines)

  echo sch[].trySend(@["done"])

proc initPlugins*() =
  gSciState.plugins = newTable[string, ptr Channel[seq[string]]]()

  for pl in walkFiles("plugins/*.nims"):
    var
      sch = newPtrChannel[seq[string]]()
    spawn startPlugin(pl, sch)
    gSciState.plugins[pl] = sch

proc syncPlugins*() =
  for pl in gSciState.plugins.keys():
    let
      (ready, lines) = gSciState.plugins[pl][].tryRecv()

    if ready:
      for line in lines:
        if line == "done":
          gSciState.plugins.del(pl)
          break

        handleCommand(line)

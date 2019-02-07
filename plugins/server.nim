import locks, os, strformat, strutils, tables, threadpool

import winim/inc/[windef, winuser]

import "../src"/pluginapi

import ".."/wrappers/nng

type
  Server = object
    lock: Lock
    run: bool
    data: seq[string]

    window: pointer
    reloadWindow: proc(window: pointer) {.nimcall.}

proc getServer(plg: var Plugin): ptr Server =
  return cast[ptr Server](plg.pluginData)

proc monitorServer(pserver: ptr Server) {.thread.} =
  var
    socket: nng_socket
    buf: cstring
    sz: cuint
    ret: cint

  if nng_bus0_open(addr socket) == 0:
    if socket.nng_listen("ipc://tmp/feud1", nil, 0) != 0:
      echo "Listen failed"
    else:
      while true:
        withLock pserver[].lock:
          if not pserver[].run:
            break

        ret = socket.nng_recv(addr buf, addr sz, (NNG_FLAG_NONBLOCK or NNG_FLAG_ALLOC).cint)
        if ret == 0:
          if sz != 0:
            withLock pserver[].lock:
              pserver[].data.add $buf
              discard InvalidateRect(cast[HWND](pserver[].window),  nil, 0)
          buf.nng_free(sz)
        elif ret == NNG_ETIMEDOUT:
          echo "Timed out"

        sleep(100)

    discard socket.nng_close()
  else:
    echo "Bus open failed"

proc initServer(plg: var Plugin) =
  var
    pserver = newShared[Server]()
  plg.pluginData = cast[pointer](pserver)

  pserver[].lock.initLock()
  pserver[].run = true

  pserver[].window = plg.ctx.editor

  spawn monitorServer(pserver)

proc stopServer(plg: var Plugin) =
  var
    pserver = plg.getServer()

  withLock pserver[].lock:
    pserver[].run = false

  sleep(100)

  freeShared(pserver)

proc readServer(plg: var Plugin) =
  var
    pserver = plg.getServer()

  withLock pserver[].lock:
    for i in pserver[].data:
      plg.ctx.handleCommand(plg.ctx, $i)

    if pserver[].data.len != 0:
      pserver[].data = @[]

feudPluginLoad:
  plg.initServer()

feudPluginTick:
  plg.readServer()

feudPluginUnload:
  plg.stopServer()

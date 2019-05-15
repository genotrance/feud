import deques, locks, os, strformat, strutils, tables

import "../src"/pluginapi

import ".."/wrappers/nng

type
  RemoteCtx = ref object
    listen: string
    dial: string
    thread: Thread[tuple[premote: ptr Remote, listen, dial: string]]

  Remote = object
    lock: Lock
    run: bool
    recvBuf: Deque[string]
    sendBuf: Deque[string]
    ack: int

proc getRemote(plg: var Plugin): ptr Remote =
  return cast[ptr Remote](plg.pluginData)

proc monitorRemote(tparam: tuple[premote: ptr Remote, listen, dial: string]) {.thread.} =
  var
    socket: nng_socket
    listener: nng_listener
    dialer: nng_dialer
    buf: cstring
    sz: cuint
    ret: cint
    run = true

  ret = nng_bus0_open(addr socket)
  doException  ret == 0, &"Failed to open bus socket: {ret}"

  if tparam.dial.len != 0:
    ret = socket.nng_dial(tparam.dial, addr dialer, 0)
    doException ret == 0, &"Failed to connect to {tparam.dial}: {ret}"
  else:
    ret = socket.nng_listen(tparam.listen, addr listener, 0)
    doException ret == 0, &"Failed to listen on {tparam.listen}: {ret}"

  while run:
    ret = socket.nng_recv(addr buf, addr sz, (NNG_FLAG_NONBLOCK or NNG_FLAG_ALLOC).cint)
    if ret == 0:
      if sz != 0:
        withLock tparam.premote[].lock:
          tparam.premote[].recvBuf.addLast $buf
      buf.nng_free(sz)
    elif ret == NNG_ETIMEDOUT:
      echo "Timed out"
    elif ret == NNG_EAGAIN:
      discard
    else:
      echo "Recv failed for some reason " & $ret

    withLock tparam.premote[].lock:
      if tparam.premote[].sendBuf.len != 0:
        buf = tparam.premote[].sendBuf.peekFirst()
        ret = socket.nng_send(buf, (buf.len+1).cuint, NNG_FLAG_NONBLOCK.cint)
        if ret notin [0, NNG_EAGAIN.int]:
          echo "Send failed for some reason " & $ret
        else:
          discard tparam.premote[].sendBuf.popFirst()

    sleep(100)

    withLock tparam.premote[].lock:
      run = tparam.premote[].run

  if tparam.dial.len != 0:
    discard dialer.nng_dialer_close()
  else:
    discard listener.nng_listener_close()

  discard socket.nng_close()

proc stopRemote(plg: var Plugin) {.feudCallback.} =
  if plg.pluginData.isNil:
    return

  var
    premote = plg.getRemote()
    premoteCtx = getCtxData[RemoteCtx](plg)

  withLock premote[].lock:
    premote[].run = false

  premoteCtx.thread.joinThread()

  if premoteCtx[].listen.len != 0:
    plg.ctx.notify(plg.ctx, "Stopped remote plugin at " & premoteCtx[].listen)

  freeShared(premote)

  plg.pluginData = nil

proc initRemote(plg: var Plugin) {.feudCallback.} =
  plg.stopRemote()

  var
    premote = newShared[Remote]()
    premoteCtx = getCtxData[RemoteCtx](plg)

  plg.pluginData = cast[pointer](premote)

  premote[].lock.initLock()
  premote[].run = true
  premote[].recvBuf = initDeque[string]()
  premote[].sendBuf = initDeque[string]()

  if plg.ctx.cmdParam.len == 0:
    if premoteCtx[].listen.len == 0:
      premoteCtx[].listen = "ipc:///tmp/feud"
  else:
    let
      (cmd, val) = plg.ctx.cmdParam[0].splitCmd()
    if val.len != 0:
      if cmd == "listen":
        premoteCtx[].listen = val
      elif cmd == "dial":
        premoteCtx[].dial = val

  createThread(premoteCtx.thread, monitorRemote, (premote, premoteCtx[].listen, premoteCtx[].dial))

  if premoteCtx[].listen.len != 0:
    plg.ctx.notify(plg.ctx, "Started remote plugin at " & premoteCtx[].listen)

proc restartRemote(plg: var Plugin) {.feudCallback.} =
  plg.initRemote()

proc readRemote(plg: var Plugin) =
  if plg.pluginData.isNil:
    return

  var
    premote = plg.getRemote()

  plg.ctx.cmdParam = @[]
  withLock premote[].lock:
    for i in premote[].recvBuf.items:
      plg.ctx.cmdParam.add $i

    premote[].recvBuf.clear()

proc sendRemote(plg: var Plugin) {.feudCallback.} =
  if plg.pluginData.isNil:
    return

  var
    premote = plg.getRemote()

  if plg.ctx.cmdParam.len != 0:
    withLock premote[].lock:
      premote[].sendBuf.addLast plg.ctx.cmdParam[0]

    plg.ctx.cmdParam = @[]

proc getAck(plg: var Plugin) {.feudCallback.} =
  if plg.pluginData.isNil:
    return

  var
    premote = plg.getRemote()

  plg.ctx.cmdParam = @[]
  withLock premote[].lock:
    if premote[].ack > 0:
      premote[].ack -= 1
      plg.ctx.cmdParam = @["ack"]

proc notifyClient(plg: var Plugin) =
  if plg.pluginData.isNil:
    return

  var
    mode = ""

  withLock plg.ctx.pmonitor[].lock:
    mode = plg.ctx.pmonitor[].path

  if mode == "server":
    plg.sendRemote()

feudPluginLoad()

feudPluginTick:
  if plg.pluginData.isNil:
    return

  var
    premote = plg.getRemote()
    mode = ""

  withLock plg.ctx.pmonitor[].lock:
    mode = plg.ctx.pmonitor[].path

  plg.readRemote()
  if plg.ctx.cmdParam.len != 0:
    if mode == "server":
      for i in plg.ctx.cmdParam:
        discard plg.ctx.handleCommand(plg.ctx, i)
        plg.ctx.cmdParam = @["ack"]
        plg.sendRemote()
    else:
      for i in plg.ctx.cmdParam:
        if i == "ack":
          withLock premote[].lock:
            premote[].ack += 1
        else:
          echo i

feudPluginNotify:
  plg.notifyClient()

feudPluginUnload:
  plg.stopRemote()

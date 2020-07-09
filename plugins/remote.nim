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

proc getRemote(plg: Plugin): ptr Remote =
  return cast[ptr Remote](plg.pluginData)

proc monitorRemote(tparam: tuple[premote: ptr Remote, listen, dial: string]) {.thread.} =
  var
    socket: nng_socket
    listener: nng_listener
    dialer: nng_dialer
    buf: cstring
    sz: uint
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

    sleep(10)

    withLock tparam.premote[].lock:
      run = tparam.premote[].run

  if tparam.dial.len != 0:
    discard dialer.nng_dialer_close()
  else:
    discard listener.nng_listener_close()

  discard socket.nng_close()

proc stopRemote(plg: Plugin, cmd: CmdData) {.feudCallback.} =
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

proc initRemote(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  plg.stopRemote(cmd)

  var
    premote = newShared[Remote]()
    premoteCtx = getCtxData[RemoteCtx](plg)

  plg.pluginData = cast[pointer](premote)

  premote[].lock.initLock()
  premote[].run = true
  premote[].recvBuf = initDeque[string]()
  premote[].sendBuf = initDeque[string]()

  if cmd.params.len == 0:
    if premoteCtx[].listen.len == 0:
      premoteCtx[].listen = "ipc:///tmp/feud"
  else:
    if cmd.params.len == 2:
      if cmd.params[0] == "listen":
        premoteCtx[].listen = cmd.params[1]
      elif cmd.params[0] == "dial":
        premoteCtx[].dial = cmd.params[1]
      else:
        cmd.failed = true
        plg.ctx.notify(plg.ctx, "Bad syntax for `initRemote()` - expect listen/dial")
    else:
      cmd.failed = true
      plg.ctx.notify(plg.ctx, "Bad syntax for `initRemote()`")

  if not cmd.failed:
    createThread(premoteCtx.thread, monitorRemote, (premote, premoteCtx[].listen, premoteCtx[].dial))

    if premoteCtx[].listen.len != 0:
      plg.ctx.notify(plg.ctx, "Started remote plugin at " & premoteCtx[].listen)

proc restartRemote(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  plg.initRemote(cmd)

proc readRemote(plg: Plugin): seq[string] =
  if plg.pluginData.isNil:
    return

  var
    premote = plg.getRemote()

  withLock premote[].lock:
    for i in premote[].recvBuf.items:
      result.add $i

    premote[].recvBuf.clear()

proc sendRemote(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  if plg.pluginData.isNil:
    return

  var
    premote = plg.getRemote()

  withLock premote[].lock:
    premote[].sendBuf.addLast cmd.params.join(" ")

proc getAck(plg: Plugin, cmd: CmdData) {.feudCallback.} =
  if plg.pluginData.isNil:
    return

  var
    premote = plg.getRemote()

  withLock premote[].lock:
    if premote[].ack > 0:
      premote[].ack -= 1
      cmd.returned = @["ack"]

proc notifyClient(plg: Plugin, cmd: CmdData) =
  if plg.pluginData.isNil:
    return

  var
    mode: PluginMode

  withLock plg.ctx.pmonitor[].lock:
    mode = plg.ctx.pmonitor[].mode

  if mode == server:
    plg.sendRemote(cmd)

feudPluginLoad()

feudPluginTick:
  if plg.pluginData.isNil:
    return

  var
    premote = plg.getRemote()
    data = plg.readRemote()
    mode: PluginMode

  withLock plg.ctx.pmonitor[].lock:
    mode = plg.ctx.pmonitor[].mode

  if data.len != 0:
    if mode == server:
      for i in data:
        var
          cmd = newCmdData(i)
        plg.ctx.handleCommand(plg.ctx, cmd)

        cmd = newCmdData("ack")
        plg.sendRemote(cmd)
    elif mode == client:
      for i in data:
        if i == "ack":
          withLock premote[].lock:
            premote[].ack += 1
        else:
          echo i

feudPluginNotify:
  plg.notifyClient(cmd)

feudPluginUnload:
  plg.stopRemote(cmd)

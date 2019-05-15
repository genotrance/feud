import cligen, os, rdstdin, strformat, strutils

import "."/src/[globals, plugin, utils]

const
  err = "Failed to send through channel locally"

var
  gCh: Channel[string]

gCh.open()

proc handleCommand(ctx: var Ctx, command: string): bool =
  let
    (cmd, val) = command.splitCmd()

  if cmd == "runHook":
    return true

  ctx.cmdParam = if val.len != 0: @[val] else: @[]
  if not ctx.handlePluginCommand(cmd):
    ctx.cmdParam = @[command]
    discard ctx.handlePluginCommand("sendRemote")

proc handleAck(ctx: var Ctx, command: string) =
  let
    (cmd, val) = command.splitCmd()
    valI = parseInt(val)
  for i in 0 .. valI-1:
    for j in 0 .. 100:
      discard handleCommand(ctx, "getAck")
      if ctx.cmdParam.len != 0:
        break
      ctx.syncPlugins()
      sleep(100)
    if ctx.cmdParam.len == 0:
      echo "Not all commands ack'd"
      quit(1)

proc messageLoop(ctx: var Ctx) =
  var
    run = executing

  while run == executing:
    let (ready, command) = gCh.tryRecv()

    if ready:
      if command == "fexit":
        run = stopped
      elif command.startsWith("ack "):
        ctx.handleAck(command)
      else:
        discard handleCommand(ctx, command)

    ctx.syncPlugins()

    sleep(100)

proc initCmd() =
  var
    run = executing

  sleep(1000)
  while run == executing:
    let
      command = readLineFromStdin("feud> ")

    if command.len != 0:
      doAssert gCh.trySend(command), err

    if command == "fexit":
      run = stopped

    sleep(100)

proc main(
    ip: string = "",
    command: seq[string],
  ) =
  var
    ctx = new(Ctx)

    server =
      if ip.len == 0:
        "ipc://tmp/feud"
      else:
        &"tcp://{ip}:3917"

    client =
      if ip.len == 0:
        "ipc://tmp/feudc"
      else:
        &"tcp://*:3918"

    thread: Thread[void]

  ctx.handleCommand = handleCommand

  ctx.initPlugins("client")

  while not ctx.ready:
    ctx.syncPlugins()

  discard handleCommand(ctx, &"initRemote dial {server}")

  if command.len == 0:
    createThread(thread, initCmd)
  else:
    for cmd in command:
      doAssert gCh.trySend(cmd), err
    if "quit" notin command and "exit" notin command:
      doAssert gCh.trySend("ack " & $command.len), err
    doAssert gCh.trySend("fexit"), err

  ctx.messageLoop()

  thread.joinThread()

when isMainModule:
  dispatch(main, help = {
    "ip": "IP address of remote server",
    "command" : "command to send server",
  }, short = {
    "ip": 'i',
  })

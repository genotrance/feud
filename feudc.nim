import cligen, os, rdstdin, strformat, strutils

import "."/src/[globals, plugin, utils]

var
  gCh: Channel[string]

gCh.open()

proc handleCommand(ctx: var Ctx, command: string): bool =
  let
    (cmd, val) = command.splitCmd()

  ctx.cmdParam = if val.len != 0: @[val] else: @[]
  if not ctx.handlePluginCommand(cmd):
    ctx.cmdParam = @[command]
    discard ctx.handlePluginCommand("sendRemote")

proc messageLoop(ctx: var Ctx) =
  var
    run = executing

  while run == executing:
    let (ready, command) = gCh.tryRecv()

    if ready:
      discard handleCommand(ctx, command)

      if command == "fexit":
        run = stopped

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
      doAssert gCh.trySend(command), "Failed to send over channel"

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

  discard ctx.handleCommand(ctx, &"initRemote dial {server}")

  if command.len == 0:
    createThread(thread, initCmd)
  else:
    for cmd in command:
      doAssert gCh.trySend(cmd), "Failed to send through channel locally"
    doAssert gCh.trySend("fexit"), "Failed to send through channel locally"

  ctx.messageLoop()

  thread.joinThread()

when isMainModule:
  dispatch(main, help = {
    "ip": "IP address of remote server",
    "command" : "command to send server",
  }, short = {
    "ip": 'i',
  })

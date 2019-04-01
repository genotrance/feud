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
    discard ctx.handlePluginCommand("sendServer")

proc messageLoop(ctx: var Ctx) =
  var
    run = true

  while run:
    let (ready, command) = gCh.tryRecv()

    if ready:
      discard handleCommand(ctx, command)

      if command == "exit":
        run = false

    ctx.syncPlugins()

    sleep(100)

proc initCmd() =
  var
    run = true

  sleep(1000)
  while run:
    let
      command = readLineFromStdin("feud> ")

    if command.len != 0:
      doAssert gCh.trySend(command), "Failed to send over channel"

    if command == "exit":
      run = false

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

  ctx.cmdParam = @[client, server]

  ctx.handleCommand = handleCommand

  ctx.initPlugins("client")

  createThread(thread, initCmd)

  ctx.messageLoop()

  thread.joinThread()

when isMainModule:
  dispatch(main, help = {
    "ip": "IP address of remote server",
    "command" : "command to send server",
  }, short = {
    "ip": 'i',
  })

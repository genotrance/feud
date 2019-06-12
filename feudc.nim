import cligen, os, rdstdin, strformat, strutils

import "."/src/[globals, plugin, utils]

const
  err = "Failed to send through channel locally"

var
  gCh: Channel[string]

gCh.open()

proc handleCommand(ctx: var Ctx, cmd: var CmdData) =
  if cmd.params.len != 0:
    if cmd.params[0] == "runHook":
      return

    ctx.handlePluginCommand(cmd)
    if cmd.failed:
      cmd.failed = false
      cmd.params = @["sendRemote"] & cmd.params
      ctx.handlePluginCommand(cmd)
  else:
    cmd.failed = true

proc handleAck(ctx: var Ctx, command: string) =
  var
    (_, val) = command.splitCmd()
    valI = parseInt(val)
    cmd = newCmdData("getAck")
  for i in 0 .. valI-1:
    cmd.returned = @[]
    for j in 0 .. 100:
      handleCommand(ctx, cmd)
      if cmd.returned.len != 0:
        break
      ctx.syncPlugins()
      sleep(100)
    if cmd.returned.len == 0:
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
        var
          cmd = newCmdData(command)
        handleCommand(ctx, cmd)

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

  var
    cmd = newCmdData(&"initRemote dial {server}")
  handleCommand(ctx, cmd)

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

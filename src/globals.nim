import segfaults, dynlib, locks, sets, tables

type
  CmdData* = ref object
    params*: seq[string]
    pparams*: seq[pointer]

    failed*: bool
    returned*: seq[string]
    preturned*: seq[pointer]

  Plugin* = ref object
    ctx*: Ctx
    name*: string
    path*: string
    handle*: LibHandle

    depends*: seq[string]
    dependents*: HashSet[string]

    onDepends*: proc(plg: var Plugin, cmd: var CmdData)
    onLoad*: proc(plg: var Plugin, cmd: var CmdData)
    onUnload*: proc(plg: var Plugin, cmd: var CmdData)
    onTick*: proc(plg: var Plugin, cmd: var CmdData)
    onNotify*: proc(plg: var Plugin, cmd: var CmdData)

    cindex*: HashSet[string]
    callbacks*: Table[string, proc(plg: var Plugin, cmd: var CmdData)]
    pluginData*: pointer

  PluginMode* = enum
    server, client

  Run* = enum
    stopped, paused, executing

  PluginMonitor* = object
    lock*: Lock
    run*: Run
    mode*: PluginMode
    load*: seq[string]
    init*: seq[string]
    processed*: HashSet[string]
    ready*: bool

  Ctx* = ref object
    run*: Run
    ready*: bool
    cli*: seq[string]

    msg*: proc(ctx: var Ctx, msgID: int, wparam: pointer = nil, lparam: pointer = nil, popup = false, windowID = -1): int
    notify*: proc(ctx: var Ctx, msg: string)
    handleCommand*: proc(ctx: var Ctx, cmd: var CmdData) {.nimcall.}

    tick*: int
    pmonitor*: ptr PluginMonitor
    plugins*: Table[string, Plugin]
    pluginData*: Table[string, pointer]

  FeudException* = object of Exception

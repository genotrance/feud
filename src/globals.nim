import dynlib, locks, sets, tables

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

    onDepends*: proc(plg: Plugin, cmd: CmdData)
    onLoad*: proc(plg: Plugin, cmd: CmdData)
    onUnload*: proc(plg: Plugin, cmd: CmdData)
    onTick*: proc(plg: Plugin, cmd: CmdData)
    onNotify*: proc(plg: Plugin, cmd: CmdData)

    cindex*: HashSet[string]
    callbacks*: Table[string, proc(plg: Plugin, cmd: CmdData)]
    pluginData*: pointer

  PluginMode* = enum
    server, client

  Run* = enum
    stopped, paused, executing

  PluginMonitor* = object
    lock*: Lock
    run*: Run
    mode*: PluginMode
    load*: HashSet[string]
    processed*: HashSet[string]
    ready*: bool

  Ctx* = ref object
    run*: Run
    ready*: bool
    cli*: seq[string]

    msg*: proc(ctx: Ctx, msgID: int, wparam: pointer = nil, lparam: pointer = nil, popup = false, windowID = -1): int
    notify*: proc(ctx: Ctx, msg: string)
    handleCommand*: proc(ctx: Ctx, cmd: CmdData) {.nimcall.}

    tick*: int
    pmonitor*: ptr PluginMonitor
    plugins*: Table[string, Plugin]
    pluginData*: Table[string, pointer]

  FeudException* = object of CatchableError

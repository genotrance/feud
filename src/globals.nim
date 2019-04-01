import segfaults, dynlib, locks, sets, tables

type
  Plugin* = ref object
    ctx*: Ctx
    name*: string
    path*: string
    handle*: LibHandle

    depends*: seq[string]
    dependents*: HashSet[string]

    onDepends*: proc(plg: var Plugin)
    onLoad*: proc(plg: var Plugin)
    onUnload*: proc(plg: var Plugin)
    onTick*: proc(plg: var Plugin)
    onNotify*: proc(plg: var Plugin)

    cindex*: HashSet[string]
    callbacks*: TableRef[string, proc(plg: var Plugin)]
    pluginData*: pointer

  PluginMonitor* = object
    lock*: Lock
    run*: bool
    path*: string
    load*: seq[string]
    init*: seq[string]
    processed*: HashSet[string]
    ready*: bool

  Ctx* = ref object
    run*: bool
    ready*: bool
    cli*: seq[string]

    msg*: proc(ctx: var Ctx, msgID: int, wparam: pointer = nil, lparam: pointer = nil, popup = false, windowID = -1): int
    notify*: proc(ctx: var Ctx, msg: string)
    handleCommand*: proc(ctx: var Ctx, command: string): bool {.nimcall.}

    tick*: int
    pmonitor*: ptr PluginMonitor
    plugins*: TableRef[string, Plugin]
    pluginData*: TableRef[string, pointer]

    cmdParam*: seq[string]
    ptrParam*: seq[pointer]

  FeudException* = object of Exception

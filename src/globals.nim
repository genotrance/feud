import segfaults, dynlib, locks, sets, tables

type
  Callback* = proc(ctx: var Ctx) {.nimcall.}
  PCallback* = proc(plg: var Plugin) {.cdecl.}

  Plugin* = ref object
    ctx*: Ctx
    name*: string
    path*: string
    handle*: LibHandle

    depends*: seq[string]
    dependents*: HashSet[string]

    cindex*: HashSet[string]
    callbacks*: TableRef[string, PCallback]
    pluginData*: pointer

  PluginMonitor* = object
    lock*: Lock
    run*: bool
    path*: string
    load*: seq[string]
    init*: seq[string]
    processed*: HashSet[string]
    window*: pointer

  Ctx* = ref object
    run*: bool

    msg*: proc(ctx: var Ctx, msgID: int, wparam: pointer = nil, lparam: pointer = nil, windowID = -1): int
    notify*: proc(ctx: var Ctx, msg: string)
    handleCommand*: proc(ctx: var Ctx, command: string) {.nimcall.}

    tick*: int
    pmonitor*: ptr PluginMonitor
    plugins*: TableRef[string, Plugin]
    pluginData*: TableRef[string, pointer]

    cmdParam*: seq[string]
    ptrParam*: seq[pointer]

  FeudException* = object of Exception

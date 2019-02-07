import dynlib, sets, tables

type
  Callback* = proc(ctx: var Ctx) {.nimcall.}
  PCallback* = proc(plg: var Plugin) {.cdecl.}

  Plugin* = ref object
    ctx*: Ctx
    name*: string
    path*: string
    handle*: LibHandle
    cindex*: HashSet[string]
    callbacks*: TableRef[string, PCallback]
    onUnload*: PCallback
    pluginData*: pointer

  Ctx* = ref object
    eMsg*: proc(msgID: int, wparam: pointer = nil, lparam: pointer = nil): int
    cMsg*: proc(msgID: int, wparam: pointer = nil, lparam: pointer = nil): int
    notify*: proc(msg: string)

    plugins*: TableRef[string, Plugin]
    pluginData*: TableRef[string, pointer]

    cmdParam*: string

converter toPtr*(val: SomeInteger): pointer =
  return cast[pointer](val)

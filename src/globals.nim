import segfaults, dynlib, locks, sets, tables, threadpool

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
    onTick*: PCallback
    onNotify*: PCallback

    pluginData*: pointer

  PluginMonitor* = object
    lock*: Lock
    run*: bool
    path*: string
    load*: seq[string]
    processed*: HashSet[string]
    window*: pointer

  Ctx* = ref object
    editor*: pointer
    command*: pointer

    eMsg*: proc(msgID: int, wparam: pointer = nil, lparam: pointer = nil): int
    cMsg*: proc(msgID: int, wparam: pointer = nil, lparam: pointer = nil): int
    notify*: proc(ctx: var Ctx, msg: string)
    handleCommand*: proc(ctx: var Ctx, command: string) {.nimcall.}

    pmonitor*: ptr PluginMonitor
    plugins*: TableRef[string, Plugin]
    pluginData*: TableRef[string, pointer]

    cmdParam*: seq[string]

  FeudException* = object of Exception

proc newShared*[T](): ptr T =
  result = cast[ptr T](allocShared0(sizeof(T)))

proc freeShared*[T](s: var ptr T) =
  s.deallocShared()
  s = nil

proc newPtrChannel*[T](): ptr Channel[T] =
  result = newShared[Channel[T]]()
  result[].open()

proc closePtrChannel*[T](sch: var ptr Channel[T]) =
  sch[].close()
  sch.freeShared()

converter toPtr*(val: SomeInteger): pointer =
  return cast[pointer](val)

template doException*(cond, msg) =
  if not cond:
    raise newException(FeudException, msg)

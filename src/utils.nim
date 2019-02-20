import "."/globals

proc newShared*[T](): ptr T =
  result = cast[ptr T](allocShared0(sizeof(T)))

proc freeShared*[T](s: var ptr T) =
  s.deallocShared()
  s = nil

# proc newPtrChannel*[T](): ptr Channel[T] =
  # result = newShared[Channel[T]]()
  # result[].open()

# proc closePtrChannel*[T](sch: var ptr Channel[T]) =
  # sch[].close()
  # sch.freeShared()

converter toPtr*(val: SomeInteger): pointer =
  return cast[pointer](val)

template doException*(cond, msg) =
  if not cond:
    raise newException(FeudException, msg)

proc toCallback*(callback: pointer): proc(plg: var Plugin) =
  if not callback.isNil:
    result = proc(plg: var Plugin) =
      cast[proc(plg: var Plugin) {.cdecl.}](callback)(plg)
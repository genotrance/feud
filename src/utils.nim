import os, strutils

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

proc toCallback*(callback: pointer): proc(plg: var Plugin, cmd: var CmdData) =
  if not callback.isNil:
    result = proc(plg: var Plugin, cmd: var CmdData) =
      cast[proc(plg: var Plugin, cmd: var CmdData) {.cdecl.}](callback)(plg, cmd)

proc splitCmd*(command: string): tuple[name, val: string] =
  let
    spl = command.strip().split(" ", maxsplit=1)
    name = spl[0]
    val = if spl.len == 2: spl[1].strip() else: ""

  return (name, val)

proc newCmdData*(command: string): CmdData =
  result = new(CmdData)
  result.params = command.parseCmdLine()

template decho*(str: untyped) =
  when not defined(release):
    echo str
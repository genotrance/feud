import cligen, os, strutils

import "src"/sci

proc main(cmds: seq[string]) =
  feudStart(cmds)

when isMainModule:
  dispatch(main)

import cligen, os, strutils

import "src"/sci

when defined(binary):
  import nimdeps

  setupDepFiles(@["feudc.exe", "feud.ini"])

  const path = gorgeEx("cmd /c cd").output.strip()
  const files = (block:
    var files: seq[string]
    for file in gorgeEx("cmd /c dir /s/b plugins").output.splitLines():
      if file.splitFile().ext in [".dll", ".xml"]:
        files.add file.replace(path, "")

    files
  )

  setupDepFiles(files)

proc main(cmds: seq[string]) =
  feudStart(cmds)

when isMainModule:
  dispatch(main)

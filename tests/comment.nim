let
  cmds = @[
    "open feud.nim",
    "eMsg SCI_SELECTALL",
    "toggleComment",
    "save",
    "close"
  ]

exec "git checkout feud.nim"

cmds.execFeudC()

doAssert gorgeEx("git diff ..\\feud.nim").output.len != 0, "File didn't change"

cmds.execFeudC()

doAssert gorgeEx("git diff ..\\feud.nim").output.len == 0, "File didn't revert"
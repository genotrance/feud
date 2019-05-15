let
  commentCmds = @[
    "open feud.nim",
    "eMsg SCI_SELECTALL",
    "toggleComment",
    "save",
    "close"
  ]

exec "git checkout feud.nim"

discard commentCmds.execFeudC()

doAssert gorgeEx("git diff ..\\feud.nim").output.len != 0, "File didn't change"

discard commentCmds.execFeudC()

doAssert gorgeEx("git diff ..\\feud.nim").output.len == 0, "File didn't revert"
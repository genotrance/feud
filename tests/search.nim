var
  srchCmds = @[
    "newDoc"
  ]

for i in 0 .. 4:
  srchCmds.add "eMsg SCI_APPENDTEXT 10 HelloWorld"

srchCmds.add "eMsg SCI_GOTOPOS 0"

for i in 0 .. 4:
  srchCmds.add @[
    "search World",
    "eMsg -v SCI_GETTARGETSTART",
    "eMsg -v SCI_GETTARGETEND"
  ]

srchCmds.add @[
  "eMsg SCI_GOTOPOS 0",
  "search Hello",
    "eMsg -v SCI_GETTARGETSTART"
]

let
  srchOut = srchCmds.execFeudC()

for i in 0 .. 10:
  doAssert srchOut.contains("Returned: " & $(i * 5))

var
  replCmds = @[
    "eMsg SCI_GOTOPOS 0",
    "replace World Universe",
    "eMsg SCI_GOTOPOS 0"
  ]

for i in 0 .. 1:
  replCmds.add @[
    "search Universe",
    "eMsg -v SCI_GETTARGETSTART",
    "eMsg -v SCI_GETTARGETEND"
  ]

let
  replOut = replCmds.execFeudC()

doAssert replOut.contains("Replaced 1 instances of 'World' with 'Universe'")
doAssert replOut.contains("Returned: 5")
doAssert replOut.contains("Returned: 13")
doAssert replOut.contains("Returned: 6")
doAssert replOut.contains("Returned: 53")

var
  repl2Cmds = @[
    "eMsg SCI_GOTOPOS 0",
    "replace World Universe -a",
    "eMsg SCI_GOTOPOS 0"
  ]

for i in 0 .. 4:
  repl2Cmds.add @[
    "search Universe",
    "eMsg -v SCI_GETTARGETSTART",
    "eMsg -v SCI_GETTARGETEND"
  ]

let
  repl2Out = repl2Cmds.execFeudC()

doAssert repl2Out.contains("Replaced 4 instances of 'World' with 'Universe'")

var
  repl2Cnt = 0
for i in 0 .. 4:
  repl2Cnt += 5
  doAssert repl2Out.contains("Returned: " & $repl2Cnt)
  repl2Cnt += 8
  doAssert repl2Out.contains("Returned: " & $repl2Cnt)

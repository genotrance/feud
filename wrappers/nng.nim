import os

import nimterop/[cimport, build]

const
  nngDir = getProjectCacheDir("feud" / "nng")

setDefines(@[
  "nngStatic"
])

when defined(Windows):
  setDefines(@[
    "nngGit",
    "nngSetVer=v1.3.0",
  ])
else:
  setDefines(@[
    "nngConan",
    "nngSetVer=1.3.0",
  ])

getHeader(
  header = "nng.h",
  giturl = "https://github.com/nanomsg/nng",
  conanuri = "nng/$1",
  outdir = nngDir,
  cmakeFlags = "-DNNG_TESTS=OFF -DNNG_TOOLS=OFF"
)

when defined(Windows):
  {.passL: "-lws2_32 -lmswsock -ladvapi32 -lkernel32".}

cDefine("NNG_DECL", "extern")
cIncludeDir(nngDir/"include")

cImport(
  @[nngDir/"include/nng/nng.h", nngDir/"include/nng/protocol/bus0/bus.h"], flags = "-E_"
)
import macros, os, strutils

import nimterop/[cimport, git]

const
  baseDir = currentSourcePath().parentDir().parentDir()/"build"
  nngDir = baseDir/"nng"

static:
  cDebug()
  gitPull("https://github.com/nanomsg/nng", nngDir, "include/*\nsrc/*")

  cDefine("NNG_STATIC_LIB")
  cDefine("NNG_DECL", "extern")

  cDefine("NNG_HAVE_BUS0")
  cDefine("NNG_HAVE_PAIR0")
  cDefine("NNG_HAVE_PULL0")
  cDefine("NNG_HAVE_PUSH0")
  cDefine("NNG_HAVE_PUB0")
  cDefine("NNG_HAVE_SUB0")
  cDefine("NNG_HAVE_REQ0")
  cDefine("NNG_HAVE_REP0")
  cDefine("NNG_HAVE_SURVEYOR0")
  cDefine("NNG_HAVE_RESPONDENT0")

  cDefine("NNG_TRANSPORT_INPROC")
  cDefine("NNG_TRANSPORT_IPC")
  cDefine("NNG_TRANSPORT_TCP")
  cDefine("NNG_TRANSPORT_WS")
#  cDefine("NNG_TRANSPORT_WSS")
#  cDefine("NNG_TRANSPORT_TLS")
#  cDefine("NNG_TRANSPORT_ZEROTIER")

when defined(Windows):
  static:
    cDefine("NNG_PLATFORM_WINDOWS")
    cDefine("_WIN32_WINNT", "0x600")
    cDefine("InterlockedAddNoFence64", "_InterlockedAdd64")

  cCompile(nngDir/"src/platform/windows")

  {.passL: "-lws2_32 -lmswsock -ladvapi32 -lkernel32".}

else:
  static:
    cDefine("NNG_PLATFORM_POSIX")

  cCompile(nngDir/"src/platform/posix")

cIncludeDir(nngDir/"include")
cIncludeDir(nngDir/"src")

cCompile(nngDir/"src/compat")
cCompile(nngDir/"src/nng.c")
cCompile(nngDir/"src/core")
cCompile(nngDir/"src/protocol")
cCompile(nngDir/"src/transport", exclude="zerotier,tls")
cCompile(nngDir/"src/supplemental", exclude="tls")

cImport(nngDir/"include/nng/nng.h")
cImport(nngDir/"include/nng/protocol/bus0/bus.h")

# Package

version     = "0.1.0"
author      = "genotrance"
description = "Fed Ep with UDitors"
license     = "MIT"

bin = @["feud", "feudc"]

# Dependencies

requires "nim >= 0.19.0", "nimterop >= 0.1.0", "winim >= 2.5.2", "cligen >= 0.9.17"

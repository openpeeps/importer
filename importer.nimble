# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "Generic file importer for building high-performance module systems"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.0"
requires "checksums"
requires "malebolgia#head"
requires "filetype"

task dev, "dev build":
  exec "nim c -d:ThreadPoolSize=8 -d:ssl -d:FixedChanSize=16 --out:./bin/importer src/importer.nim"
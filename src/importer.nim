# A generic file importer that can be used
# by hand-crafted parsers and interpreters to
# build high performance import module systems
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/importer

import pkg/checksums/md5
import pkg/[malebolgia, malebolgia/lockers, malebolgia/ticketlocks]
import std/[os, uri, strutils, tables, httpclient]

export malebolgia, lockers, ticketlocks

type
  ImportFile* = ref object
    path, source*: string
    cached: bool
    info*: FileInfo

  ImportQueue* = seq[string]
  ImportResolved = TableRef[string, ImportFile]
  
  ImportSourcePolicy* = enum
    localSourcePolicy
    remoteSourcePolicy
    anySourcePolicy

  ImportErrorMessage* = enum
    importCircularError
    importDuplicateFile
    importNotFound

  ImportPolicy* = ref object # todo
    case sourcePolicy: ImportSourcePolicy
    of remoteSourcePolicy, anySourcePolicy:
      client: HttpClient
      secured: bool = true
      whitelist: seq[Uri]
    else: discard
    extensions: seq[string]

  Import*[T] = ref object
    handle*: T
    master: Master
    resolved: ImportResolved 
    mainFilePath, mainDirPath, mainId: string
    fails: seq[tuple[reason: ImportErrorMessage, fpath: string]]
    failed: bool

  ImportHandle*[T] = proc(imp: Import[T], file: ImportFile, ticket: ptr TicketLock): seq[string] {.gcsafe, nimcall.}
  ImportError* = object of CatchableError

proc newImport*[T](path: string, basepath = "", baseIsMain = false): Import[T] =
  ## Create a new `Import` handle.
  ## Set `baseIsMain` in case imports are stored in a
  ## different directory than `path`. A real case example
  ## is Tim Template Engine, that stores `layouts`, `views`
  ## and `partials` in separate directories.
  if not isAbsolute(path):
    var basepath =
      if basepath.len == 0: path.parentDir
      else: basepath
    var path = normalizedPath(basepath / path)
  if likely(path.fileExists):
    return Import[T](
      mainFilePath: path,
      mainDirPath: if baseIsMain: basepath else: path.parentDir(),
      resolved: ImportResolved(),
      master: createMaster()
    )
  raise newException(ImportError, "Main file not found\n" & path)

proc error[T](i: Import[T], reason: ImportErrorMessage, fpath: string) =
  add i.fails, (reason, fpath)
  if not i.failed: i.failed = true

proc resolver[T](i: Locker[Import[T]], m: MasterHandle, fpath: string,
      parseHandle: ptr ImportHandle[T], ticket: ptr TicketLock) {.gcsafe.} =
  lock i as imp:
    var fpath = fpath
    if not fpath.isAbsolute:
      fpath = normalizedPath(imp.mainDirPath / fpath)
    if likely(fpath.fileExists()):
      if likely(fpath != imp.mainFilePath):
        if not imp.resolved.hasKey(fpath):
          # parse a new file
          var importFile = ImportFile(path: fpath, source: readFile(fpath))
          imp.resolved[fpath] = importFile
          imp.resolved[fpath].cached = true
          let fpaths: seq[string] = parseHandle[](imp, importFile, ticket)
          if fpaths.len > 0:
            for otherpath in fpaths:
              imp.master.spawn resolver(i, imp.master.getHandle, otherpath, parseHandle, ticket)
        else:
          # reuse imported file
          discard parseHandle[](imp, imp.resolved[fpath], ticket)
      else: imp.error(importCircularError, fpath)
    else:
      imp.error(importNotFound, fpath)

proc imports*[T](imp: Import[T], files: seq[string], parseHandle: ImportHandle[T]) =
  var isolateImp = initLocker(imp)
  var ticket = initTicketLock()
  imp.master.awaitAll:
    for fpath in files:
      imp.master.spawn resolver(isolateImp, imp.master.getHandle, fpath, addr(parseHandle), addr(ticket))

proc isCached*(importFile: ImportFile): bool =
  ## Check if `ImportFile` is cached
  importFile.cached

proc getImportPath*(importFile: ImportFile): string =
  ## Get absolute path of `ImportFile`
  importFile.path

proc hasError*[T](imp: Import[T]): bool = imp.failed
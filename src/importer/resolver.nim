import std/[critbits, tables, strutils]
export critbits

type
  ResolverNotificationType* = enum
    warningDuplicateImport
    errorCircularImport

  ResolverTree* = array[2, int] # line, column

  ResolverNotification* = tuple[
    message: ResolverNotificationType,
    trace: ResolverTree
  ]

  DependencyTree* = CritBitTree[void]
  
  ModuleNotification* = OrderedTableRef[string, seq[ResolverNotification]]
  
  Resolver* = ref object
    tree: CritBitTree[DependencyTree]
    messages: ModuleNotification

  DependencyError* = object of CatchableError

proc initResolver*(useSemver = false): Resolver =
  Resolver(messages: ModuleNotification())

proc notify(module: Resolver, path: string,
    msg: ResolverNotificationType, trace: ResolverTree) =
  if not module.messages.hasKey(path):
    module.messages[path] = @[(msg, trace)]
  else:
    module.messages[path].add((msg, trace))

proc indexModule*(man: Resolver; a: string) =
  if not man.tree.hasKey(a):
    man.tree[a] = DependencyTree()

proc incl*(man: Resolver; a, b: string; trace: ResolverTree) =
  if man.tree.hasKey(a):
    if likely(not man.tree[a].hasKey(b)):
      man.tree[a].incl(b)
      man.indexModule(b)
      man.tree[b].incl(a)
    # else:
      # man.notify(a, errorCircularImport, trace)

proc excl*(man: Resolver, x: string) =
  if man.tree.hasKey(x):
    man.tree.excl(x)

proc hasDep*(man: Resolver, a, b: string): bool =
  ## Check if `a` has a dependency for `b`
  if man.tree.hasKey(a):
    result = man.tree[a].hasKey(b)

proc hasDeps*(man: Resolver, a: string): bool =
  result = man.tree.hasKey(a)
  if result:
    return man.tree[a].len > 0

iterator dependencies*(man: Resolver, a: string): string =
  if man.tree.hasKey(a):
    for x in man.tree[a]:
      yield x

proc hasNotifications*(module: Resolver,
    path: string): bool =
  module.messages.hasKey(path)

proc getNotifications*(module: Resolver,
    path: string): seq[ResolverNotification] =
  module.messages[path]

proc getNotifications*(module: Resolver): ModuleNotification =
  module.messages

iterator notifications*(module: Resolver): (string, ResolverNotification) =
  for path, msgs in module.messages:
    for msg in msgs:
      yield (path, msg)

when isMainModule:
  var depman = initResolver()
  depman.incl("/views/index.timl", [1, 1])
  depman.incl("/views/index.timl", "/partials/foot.timl", [1, 1])
  depman.incl("/views/index.timl", "/partials/foot2.timl", [1, 1])
  depman.incl("/partials/foot.timl", "/partials/x.timl", [1, 1])
  depman.incl("/partials/x.timl", "/partials/y.timl", [1, 1])
  echo depman.tree

  for path, notification in depman.notifications:
    echo path
    echo notification
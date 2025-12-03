


suite "Reactive Operators Test Suite":

  # -----------------------------
  # MAP
  # -----------------------------
  test "map: transforms emitted values":
    notifier src(x:int, y:int)
    map(src, proc(x:int,y:int):int = x + y, int) 

    var result = 0
    mapper.connect(proc(r:int) = result = r)

    src.emit((2,3))
    check result == 5

    src.emit((10,1))
    check result == 11


  # -----------------------------
  # FILTER
  # -----------------------------
  test "filter: only passes values that match condition":
    notifier src(x:int, y:int)
    filter(src, proc(x:int,y:int):bool = x > y)

    var count = 0
    filt.connect(proc(v:int,t:int) = count.inc)

    src.emit((5,3))   # pass
    src.emit((1,9))   # blocked
    src.emit((8,2))   # pass

    check count == 2


  # -----------------------------
  # FOLD
  # -----------------------------
  test "fold: accumulates values over time":
    notifier src(x:int, y:int)
    fold(src, 0, proc(acc:tuple[acc:int], x:(int,int)):int = acc[0] + x[0])

    var finalAcc = 0
    fol.connect(proc(v:int) = finalAcc = v)

    src.emit((1,2))   # 1
    src.emit((2,3))   # 3
    src.emit((5,4))   # 8

    check finalAcc == 8


  # -----------------------------
  # MERGE
  # -----------------------------
  test "merge: forwards events from both sources":
    notifier a(x:int)
    notifier b(x:int)
    enable_value(a)
    enable_value(b)
    merge(a, b)

    var seqRes: seq[int] = @[]
    mer.connect(proc(a:tuple[x:int], b:tuple[x:int]) = seqRes.add(a[0]+b[0]))

    a.emit((x:10))
    b.emit((x:5))
    a.emit((x:2))

    check seqRes == @[10, 15, 7]


  # -----------------------------
  # ZIP
  # -----------------------------
  test "zip: emits combined values":
    notifier a(x:int)
    notifier b(x:int)
    enable_value(a)
    enable_value(b)
    zip(a, b, proc(x:tuple[x:int],y:tuple[x:int]):int = x[0] * y[0], int)

    var res: seq[int] = @[]
    mer.connect(proc(v:int) = res.add(v))

    a.emit((x:2))       # no emit yet (b missing)
    b.emit((x:4))       # now emits 2*4=8

    a.emit((x:3))       # emits 3*4 = 12
    b.emit((x:10))      # emits 3*10 = 30

    check res == @[0, 8, 12, 30]

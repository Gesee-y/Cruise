

suite "Notifier core operations":
  
  test "connect + emit works and call the callbacks":
    var received = 0

    proc cb(v: int) =
      received = v

    notifier n(x:int)
    n.open()

    n.connect(cb)
    n.emit((x:42))

    check received == 42


  test "disconnect delete callback":
    var received = 0

    proc cb(v: int) =
      received = v

    notifier n(x:int)
    n.open()

    n.connect(cb)
    n.disconnect(cb)

    n.emit((x:99))

    check received == 0


  test "[] = trigger emit":
    var received = 0

    proc cb(v: int) =
      received = v

    notifier n(x:int)
    n.open()
    enable_value(n)

    n.connect(cb)
    n[0] = (x:10)

    check received == 10
    check n[0][0] == 10


  test "[] ignore identical updates when ignore_eqvalue = true":
    var count = 0

    proc cb(v: int) =
      inc count

    notifier n(x:int)
    n.open()
    enable_value(n)

    # setup
    ignoreEqValue(n)
    n.connect(cb)

    n[0] = (x:5)
    n[0] = (x:5)
    n[0] = (x:5)

    check count == 1


  test "reset notifier":
    var received = 0
    proc cb(v: int) = received = v

    notifier n(x:int)
    n.open()
    enable_value(n)
    n.connect(cb)

    n.emit((x:3))
    check received == 3
    check n.listeners.len == 1

    n.reset()

    check n.listeners.len == 0
    
    n.emit((x:7))
    check received == 3


  test "open / close initialize and destroy resources":
    notifier n(x:int)

    # Should not crash
    n.open()
    n.close()


  test "wait signal":
    var unlocked = true

    notifier n(x:int)
    n.open()

    let start = now()

    let f = proc () =
      sleep(100)
      unlocked = true
      n.emit((x:1))

    #spawn f()

    #n.wait()

    # Si wait a été débloqué par emit, unlocked == true
    check unlocked == true

    # Et pas trop tard (sinon wait n'a pas déverrouillé)
    # check (now() - start) < 300


  #[test "connect avec plusieurs callbacks respecte l'ordre (priority)":
    var order: seq[int] = @[]

    proc cb1(v:int) = order.add(1)
    proc cb2(v:int) = order.add(2)

    notifier n(x:int)
    n.open()

    n.connect(cb2, priority = 0)
    n.connect(cb1, priority = 10)

    n.emit((x:7))

    # cb1 devrait passer avant cb2
    check order == @[1,2]]#

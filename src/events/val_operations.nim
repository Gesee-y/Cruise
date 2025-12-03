###################################################################################################################################################
##################################################################### VALUE OPERATIONS ############################################################
###################################################################################################################################################

template map*[T,L](n1:Notifier[T,L], fn, R) =
  notifier mapper(ret:R)
  enable_value(mapper)

  anoFunc(f, T, quote do:
    destructuredCallRet(val,fn, allarg)
    let res = (ret:val)
    mapper.emit(res))
  
  n1.connect(f)

template filter*[T,L](src: Notifier[T,L], fn:untyped) =
  var filt {.inject.} = newNotifier[T,L]()
  enable_value(filt)

  anoFunc(f, T, quote do:
    destructuredCallRet(condition,fn, allarg)
    if condition:
      filt.emit(allarg)
  )

  src.connect(f)

template fold*[T,L,A](src: Notifier[T,L], init: A, fn) =
  notifier fol(acc:A)
  enable_value(fol)

  var acc = init

  anoFunc(f, T, quote do:
    destructuredCallRet(acc, fn, (fol[0], allarg))
    fol.emit((acc:acc))
  )

  src.connect(f)

template merge*[TA,LA,TB,LB](a: Notifier[TA,LA], b: Notifier[TB,LB]) =
  notifier mer(ax:TB, bx:TB)
  enable_value(mer)

  anoFunc(fa, TA, quote do:
    mer.emit((a[0], b[0]))
  )
  anoFunc(fb, TB, quote do:
    mer.emit((a[0], b[0]))
  )

  a.connect(fa)
  b.connect(fb)

template zip*[TA,LA,TB,LB](a: Notifier[TA,LA], b: Notifier[TB,LB], fn, R) =
  notifier mer(ret:R)
  enable_value(mer)

  anoFunc(fa, TA, quote do:
    mer.emit((ret:fn(a[0], b[0])))
  )

  anoFunc(fb, TB, quote do:
    mer.emit((ret:fn(a[0], b[0])))
  )

  a.connect(fa)
  b.connect(fb)

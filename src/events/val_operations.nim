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

template filter*[T,L](src: Notifier[T,L], fn) =
  filt = newNotifier[T,L]()
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
    acc = fn(fol[], allargs)
    fol.emit((acc:acc))
  )

  src.connect(f)

template merge*[T,L](a: Notifier[T,L], b: Notifier[T,L]) =
  notifier mer(T)
  enable_value(mer)

  anoFunc(fa, T, quote do:
    mer.emit(allarg)
  )
  anoFunc(fb, T, quote do:
    mer.emit(allarg)
  )

  a.connect(fa)
  b.connect(fb)

template zip*[TA,LA,TB,LB](a: Notifier[TA,LA], b: Notifier[TB,LB], fn, R) =
  notifier mer(ret:R)
  enable_value(mer)

  anoFunc(fa, TA, quote do:
    let va = allarg
    if hb:
      mer.emit((ret:fn(va, vb)))
  )

  anoFunc(fb, TB, quote do:
    let vb = allarg
    if ha:
      mer.emit((ret:fn(va, vb)))
  )

  a.connect(fa)
  b.connect(fb)

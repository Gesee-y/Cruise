###################################################################################################################################################
##################################################################### VALUE OPERATIONS ############################################################
###################################################################################################################################################

##[
Transform emitted values using a mapping function.
  
Creates a new notifier that applies a transformation function to each value emitted
by the source notifier and emits the transformed result.
  
Parameters:
  - `n1`: Source notifier to map from
  - `fn`: Transformation function to apply to each emitted value
  - `R`: Return type specification for the mapped values
  
Returns:
  A new notifier named `mapper` that emits transformed values
  
Example:
```nim
notifier(numbers, value: int)
numbers.open()
    
# Map integers to their doubles
map(numbers, proc(value: int): int = value * 2, int)
mapper.open()
    
proc onMapped(ret: int) =
  echo "Doubled: ", ret
    
mapper.connect(onMapped)
numbers.emit((value: 5))  # Prints "Doubled: 10"
```
]##
template map*[T,L](n1:Notifier[T,L], fn, R):untyped =
  
  notifier mapper(ret:R)
  enable_value(mapper)
  anoFunc(f, T, quote do:
    destructuredCallRet(val,fn, allarg)
    let res = (ret:val)
    mapper.emit(res))
  
  n1.connect(f)
  mapper

##[
Filter emitted values based on a predicate function.
  
Creates a new notifier that only emits values from the source notifier
when they satisfy the given predicate condition.
  
Parameters:
 - `src`: Source notifier to filter
 - `fn`: Predicate function that returns true for values to keep
  
Returns:
 A new notifier named `filt` (injected) that emits only filtered values
  
Example:
```nim
notifier numbers(value: int)
numbers.open()
    
# Filter to only emit even numbers
filter(numbers, proc(value: int): bool = value mod 2 == 0)
filt.open()
    
proc onFiltered(value: int) =
  echo "Even number: ", value
    
filt.connect(onFiltered)
numbers.emit((value: 4))  # Prints "Even number: 4"
numbers.emit((value: 5))  # Nothing printed
```
]##
template filter*[T,L](src: Notifier[T,L], fn:untyped):untyped =
  var filt {.inject.} = newNotifier[T,L]()
  enable_value(filt)

  anoFunc(f, T, quote do:
    destructuredCallRet(condition,fn, allarg)
    if condition:
      filt.emit(allarg)
  )
  src.connect(f)
  filt

##[
Accumulate values from a notifier using a folding function.
  
Creates a new notifier that maintains an accumulated state, updating it
with each emission from the source notifier using the provided function.
Similar to reduce/fold operations in functional programming.
  
Parameters:
  - `src`: Source notifier to fold over
  - `init`: Initial accumulator value
  - `fn`: Function that takes (accumulator, value) and returns new accumulator
  
Returns:
  A new notifier named `fol` that emits the current accumulated value
  
Example:
```nim
notifier numbers(value: int)
numbers.open()
    
# Sum all emitted numbers
fold(numbers, 0, proc(acc: int, value: int): int = acc + value)
fol.open()
    
proc onSum(acc: int) =
  echo "Current sum: ", acc
    
fol.connect(onSum)
numbers.emit((value: 5))   # Prints "Current sum: 5"
numbers.emit((value: 3))   # Prints "Current sum: 8"
numbers.emit((value: 2))   # Prints "Current sum: 10"
```
]##
template fold*[T,L,A](src: Notifier[T,L], init: A, fn) =
  notifier fol(acc:A)
  enable_value(fol)
  var acc = init
  anoFunc(f, T, quote do:
    destructuredCallRet(acc, fn, (fol[0], allarg))
    fol.emit((acc:acc))
  )
  src.connect(f)

##[
Merge two notifiers into one that emits both values as a pair.
  
Creates a new notifier that emits a tuple containing the current values
from both source notifiers whenever either one emits.
  
Parameters:
  - `a`: First source notifier
  - `b`: Second source notifier
  
Returns:
  A new notifier named `mer` that emits (a_value, b_value) pairs
  
Example:
```nim
notifier mouseX(x: int)
notifier mouseY(y: int)
mouseX.open()
mouseY.open()
    
merge(mouseX, mouseY)
mer.open()
    
proc onPosition(ax: tuple[x:int], bx: tuple[y:int]) =
  echo "Position: (", ax.x, ", ", bx.y, ")"
    
mer.connect(onPosition)
mouseX.emit((x: 10))  # Prints "Position: (10, 0)"
mouseY.emit((y: 20))  # Prints "Position: (10, 20)"
```
]##
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

##[
Combine two notifiers using a custom function.
  
Creates a new notifier that applies a combining function to the current values
from both source notifiers whenever either one emits.
  
Parameters:
  - `a`: First source notifier
  - `b`: Second source notifier
  - `fn`: Function that combines values from both notifiers
  - `R`: Return type specification for the combined result
  
Returns:
  A new notifier named `mer` that emits combined values
  
Example:
```nim
notifier width(w: int)
notifier height(h: int)
width.open()
height.open()
    
# Calculate area whenever width or height changes
zip(width, height, 
    proc(w: tuple[w: int], h: tuple[h: int]): int = w.w * h.h, 
    int)
mer.open()
    
proc onArea(ret: int) =
  echo "Area: ", ret
    
mer.connect(onArea)
width.emit((w: 10))   # Prints "Area: 0"
height.emit((h: 5))   # Prints "Area: 50"
width.emit((w: 20))   # Prints "Area: 100"
```
]##
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
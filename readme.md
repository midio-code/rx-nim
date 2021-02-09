# Reactive programming in nim

An implementation of [ReactiveX](http://reactivex.io/) in Nim. It is stilly very much in an alpha stage.

# Observable[T]

## Subjects

Are observables that also stores values and can be used as observable containers.

If you need to pass a subject to a proc that expects an Observable, the `subject` can be treated as an observable by accessing its `source` field.

```nim
let foo = behaviorSubject(123)
let bar = foo.source.map(
	proc(f: int): int =
		f * f
)
```

### BehaviorSubject

Create by

```nim
let val: Subject[T] = behaviorSubject(defaultValue)
```

A BehaviorSubject pushes its current value as soon as it is subscribed to.

### Subject

Only pushes when it receives new value, meaning it won't push its current value when subscribed to.

## Operators

### .then[T](first: Observable[T], second: Observable[T]): Observable[T]

Consumes items from `first` until it completes, and then consumes all items from `second`.

###  map[T,R](self: Observable[T], mapper: T -> R): Observable[R]

Maps all items pushed by `self` using the supplied `mapper` function, returning a new `Observable` that pushes the mapped values.

### template extract[T](self: Observable[T], prop: untyped): untyped

Short hand for mapping and extracting a field from an observable.

Example:
```nim
type
   Foo = object
     bar: string
let items = behaviorSubject(Foo(bar: "baz"))
let bars = items.extract(bar)
```

### filter[T](self: Observable[T], predicate: (T) -> bool): Observable[T]

Returns a new observable that only pushes the items for which `predicate` returns true.

### combineLatest[A,B,R](a: Observable[A], b: Observable[B], mapper: (A,B) -> R): Observable[R]

Combines the output of two observables using a mapper function. The resulting observable only pushes a value when both `a` and `b` has pushed, and then whenever any of `a` or `b` pushes.

`combineLatest` is also implemented for 3, 4 and 5 arguments.

### merge[A](a: Observable[A], b: Observable[A]): Observable[A]

Combines two observables of the same type by merging their streams into one.

`merge` is also implemented for `Observable[Observable[A]]`

### switch[A](observables: Observable[Observable[A]]): Observable[A] =

Subscribes to each inner observable after first unsubscribing from the previous, effectively merging their outputs by pushing their content one after the other.

### distinctUntilChanged[T](self: Observable[T]): Observable[T] =

Only pushes if the new value is different from the previous value.


### take[T](self: Observable[T], num: int): Observable[T] =

Pushes `num` values from `self` and then completes.

# ObservableCollection

TODO

# ObservableTable

TODO


# Reactive programming in nim

[![nimble](https://raw.githubusercontent.com/yglukhov/nimble-tag/master/nimble_js.png)](https://github.com/yglukhov/nimble-tag)

An implementation of [ReactiveX](http://reactivex.io/) in Nim. It is stilly very much in an alpha stage.

# Observable

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

New values can be pushed to a subject by using the `.next(T)` function, or the `<-` operator:

```nim
let foo = behaviorSubject(123)
foo.next(321)
foo <- 222
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

### Then

```nim
then[T](first: Observable[T], second: Observable[T]): Observable[T]
```

Consumes items from `first` until it completes, and then consumes all items from `second`.

### Map

```nim
map[T,R](self: Observable[T], mapper: T -> R): Observable[R]
```

Maps all items pushed by `self` using the supplied `mapper` function, returning a new `Observable` that pushes the mapped values.

### Extract

```nim
template extract[T](self: Observable[T], prop: untyped): untyped
```

Short hand for mapping and extracting a field from an observable.

Example:
```nim
type
   Foo = object
     bar: string
let items = behaviorSubject(Foo(bar: "baz"))
let bars = items.extract(bar)
```

### Filter

```nim
filter[T](self: Observable[T], predicate: (T) -> bool): Observable[T]
```

Returns a new observable that only pushes the items for which `predicate` returns true.

### CombineLatest

```nim
combineLatest[A,B,R](a: Observable[A], b: Observable[B], mapper: (A,B) -> R): Observable[R]
```

Combines the output of two observables using a mapper function. The resulting observable only pushes a value when both `a` and `b` has pushed, and then whenever any of `a` or `b` pushes.

`combineLatest` is also implemented for 3, 4 and 5 arguments.

### Merge

```nim
merge[A](a: Observable[A], b: Observable[A]): Observable[A]
```

Combines two observables of the same type by merging their streams into one.

`merge` is also implemented for `Observable[Observable[A]]`

### Switch

```nim
switch[A](observables: Observable[Observable[A]]): Observable[A] =
```

Subscribes to each inner observable after first unsubscribing from the previous, effectively merging their outputs by pushing their content one after the other.

### DistinctUntilChanged

```nim
distinctUntilChanged[T](self: Observable[T]): Observable[T] =
```

Only pushes if the new value is different from the previous value.


### Take

```nim
take[T](self: Observable[T], num: int): Observable[T] =
```

Pushes `num` values from `self` and then completes.

# ObservableCollection

Observable collections observables that contains a list of items, and pushes information about when items are added, removed, or changed.

## CollectionSubject

Just like with Subject, a CollectionSubject contains a list of data that can be observed. Create a new CollectionSubject using:

```nim
let collection = observableCollection(@['a', 'b', 'c']) # optional default items
```

### Add

```nim
add[T](self: CollectionSubject[T], item: T): void
```

### Remove

```nim
remove[T](self: CollectionSubject[T], item: T): void
```

### Set

```nim
set[T](self: CollectionSubject[T], index: int, newVal: T): void
```

### Len


### Cache

```nim
cache[T](self: ObservableCollection[T]): CollectionSubject[T]
```

### AsObservableCollection

```nim
asObservableCollection[T](values: seq[Observable[T]]): CollectionSubject[T]
```

### Map

```nim
map[T,R](self: ObservableCollection[T], mapper: T -> R): ObservableCollection[R]
```

### Filter

```nim
filter[T](self: ObservableCollection[T], predicate: T -> bool): ObservableCollection[T]
```

### ToObservable

```nim
toObservable[T](self: CollectionSubject[T]): Observable[seq[T]]
```

### CombineLatest

```nim
combineLatest[A,B,R](a: ObservableCollection[A], b: ObservableCollection[B], mapper: (A,B) -> R): ObservableCollection[R]
```

### FirstWhere

```nim
firstWhere[T](self: ObservableCollection[T], predicate: T -> bool): Observable[Option[T]]
```

### & (concat)

```nim
`&`[T](self: ObservableCollection[T], other: ObservableCollection[T]): ObservableCollection[T]
```

# ObservableTable

## Set

```nim
set[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey, value: TValue): void
```

## Delete

```nim
delete[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): Option[TValue]
```

## Get

Since the table might change, getting a value returns an observable of an optional value. The value for a key will for example become none if someone deletes it from the table using `delete`.

```nim
get[TKey, TValue](self: ObservableTable[TKey, TValue], key: TKey): Observable[Option[TValue]]
```

The key can also itself be an observable

```nim
get[TKey, TValue](self: ObservableTable[TKey,TValue], key: Observable[TKey]): Observable[Option[TValue]]
```

## Keys

```nim
keys[TKey, TValue](self: ObservableTable[TKey, TValue]): ObservableCollection[TKey]
```

### Values

```nim
values[TKey, TValue](self: ObservableTable[TKey, TValue]): ObservableCollection[TValue]
```

## Operators

### Map

```nim
map[K,V,KR,VR](self: ObservableTable[K,V], mapper: (K,V) -> (KR,VR)): ObservableTable[KR,VR]
```

### Filter

```nim
filter[K,V](self: ObservableTable[K,V], predicate: (K,V) -> bool): ObservableTable[K,V]
```

## Helpers

### ToObservableTable

```nim
toObservableTable[TKey, TValue](self: Observable[seq[TKey]], mapper: TKey -> TValue): ObservableTable[TKey, TValue]
```

or


```nim
toObservableTable[T, TKey, TValue](self: ObservableCollection[T], mapper: T -> (TKey, TValue)): ObservableTable[TKey, TValue]
```

### MapToTable

```nim
mapToTable[TKey, TValue](self: ObservableCollection[TKey], mapper: TKey -> TValue): ObservableTable[TKey, TValue]
```


### GetCurrenctValue

```nim
getCurrentValue[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): Option[TValue]
```

### GetFirstKeyForValue

```nim
getFirstKeyForValue[TKey, TValue](self: TableSubject[TKey, TValue], value: TValue): Option[TKey]
```


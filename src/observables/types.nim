import options, sugar, tables, hashes, typetraits, strformat

type
  Error* = string

  Subscriber*[T] =  ref object
    disposed*: bool
    onNext*: (T) -> void
    onCompleted*: Option[() -> void]
    onError*: Option[(Error) -> void] ## \
    ## A subscriber is just a procedure that takes in the new value of the observable

  Subscription* = ref object
    dispose*: () -> void

  Observable*[T] = ref object
    onSubscribe*: (Subscriber[T]) -> Subscription ## \
    ## An observable is a procedure which when called with a subscriber as its argument
    ## creates a subscription, which causes the subscriber proc to get called whenever
    ## the value of the observable changes.
    ##
    ## Note that currently, the observable doesn't have any way of removing subscriptions.
    ## This must be added in the future as this feature becomes necessity.

  Subject*[T] = ref object
    ## A subject is an object that contains an observable source, maintains a list of subscribers
    ## and also keeps a reference or copy to the last value of the observable source.
    ## One has to use either a ``behaviorSubject`` or normal ``subject`` in order to create an observable
    ## over a value.
    source*: Observable[T]
    value*: T
    didComplete*: bool
    subscribers*: seq[Subscriber[T]]

  ChangeKind* {.pure.} = enum
    Added, Removed, Changed, InitialItems

  Change*[T] = object
    case kind*: ChangeKind
    of ChangeKind.Added:
      newItem*: T
      addedAtIndex*: int
    of ChangeKind.Removed:
      removedItem*: T
      removedFromIndex*: int
    of ChangeKind.Changed:
      changedAtIndex*: int
      oldVal*: T
      newVal*: T
    of ChangeKind.InitialItems:
      items*: seq[T]

  CollectionSubscriber*[T] = ref object
    onChanged*: Change[T] -> void

  ObservableCollection*[T] = ref object
    onSubscribe*: CollectionSubscriber[T] -> Subscription

  CollectionSubject*[T] = ref object
    source*: ObservableCollection[T]
    values*: seq[T]
    subscribers*: seq[CollectionSubscriber[T]]


  TableSubscriber*[TKey, TValue] = ref object
    onSet*: (TKey, TValue) -> void
    onDeleted*: (TKey, TValue) -> void

  ObservableTable*[TKey, TValue] = ref object
    onSubscribe*: (TableSubscriber[TKey, TValue]) -> Subscription

  TableSubject*[TKey, TValue] = ref object
    source*: ObservableTable[TKey, TValue]
    items*: OrderedTableRef[TKey, TValue]
    subscribers*: seq[TableSubscriber[TKey, TValue]]

proc `&`*(a,b: Subscription): Subscription =
  Subscription(
    dispose:
      proc(): void =
        a.dispose()
        b.dispose()
  )

proc `$`*[T](a: Observable[T]): string =
  "Observable of " & name(T)

proc `$`*[T](a: Subject[T]): string =
  "Subject of " & name(T)

proc `$`*[T](a: ObservableCollection[T]): string =
  "Collection of " & name(T)

proc `$`*[T](self: Change[T]): string =
  case self.kind:
    of Added:
      &"added({self.newItem}, {self.addedAtIndex})"
    of Removed:
      &"removed({self.removedItem}, {self.removedFromIndex})"
    of Changed:
      &"changed({self.changedAtIndex}, {self.oldVal}, {self.newVal})"
    of InitialItems:
      &"initialItems({self.items.len})"

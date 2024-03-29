import sugar, options, sequtils, tables, hashes, sets
import types
import observables
import utils

proc observableCollection*[T](values: seq[T] = @[]): CollectionSubject[T] =
  let subject = CollectionSubject[T](
    values: values
  )
  subject.source = ObservableCollection[T](
    onSubscribe: proc(subscriber: CollectionSubscriber[T]): Subscription =
      subject.subscribers.add(subscriber)
      subscriber.onChanged(
        Change[T](
          kind: ChangeKind.InitialItems,
          items: subject.values
        )
      )
      Subscription(
        dispose: proc(): void =
          subject.subscribers.remove(subscriber)
      )
  )
  subject

proc constantCollection*[T](values: seq[T] = @[]): CollectionSubject[T] =
  CollectionSubject[T](
    source: ObservableCollection[T](
      onSubscribe: proc(subscriber: CollectionSubscriber[T]): Subscription =
        subscriber.onChanged(
          Change[T](
            kind: ChangeKind.InitialItems,
            items: values
          )
        )
        Subscription(dispose: proc(): void = discard)
    )
  )

proc add*[T](self: CollectionSubject[T], item: T): void =
  let index = self.values.len
  self.values.add(item)
  # NOTE: Copying the subscriber list because the subscriber list might change while we're iiterating
  let subs = self.subscribers
  for subscriber in subs:
    subscriber.onChanged(
      Change[T](
        kind: ChangeKind.Added,
        newItem: item,
        addedAtIndex: index
      )
    )

proc pop*[T](self: CollectionSubject[T]): T =
  let index = self.values.len - 1
  let ret = self.values.pop()
  let subs = self.subscribers
  for subscriber in subs:
    subscriber.onChanged(
      Change[T](
        kind: ChangeKind.Removed,
        removedItem: ret,
        removedFromIndex: index
      )
    )
  return ret

proc insert*[T](self: CollectionSubject[T], item: T, index: int): void =
  self.values.insert(item, index)
  # NOTE: Copying the subscriber list because the subscriber list might change while we're iiterating
  let subs = self.subscribers
  for subscriber in subs:
    subscriber.onChanged(
      Change[T](
        kind: ChangeKind.Added,
        newItem: item,
        addedAtIndex: index
      )
    )

proc remove*[T](self: CollectionSubject[T], item: T): void =
  let index = self.values.find(item)
  if index >= self.values.len or index < 0:
    raise newException(Exception, "Tried to remove an item that was not in the collection.")
  self.values.delete(index)

  # NOTE: Copying the subscriber list because the subscriber list might change while we're iiterating
  let subs = self.subscribers
  for subscriber in subs:
    subscriber.onChanged(
      Change[T](
        kind: ChangeKind.Removed,
        removedItem: item,
        removedFromIndex: index
      )
    )

proc removeAt*[T](self: CollectionSubject[T], index: int): void =
  if index >= self.values.len or index < 0:
    raise newException(Exception, "Tried to remove an item that was not in the collection.")
  let item = self.values[index]
  self.values.delete(index)

  # NOTE: Copying the subscriber list because the subscriber list might change while we're iiterating
  let subs = self.subscribers
  for subscriber in subs:
    subscriber.onChanged(
      Change[T](
        kind: ChangeKind.Removed,
        removedItem: item,
        removedFromIndex: index
      )
    )

proc removeWhere*[T](self: CollectionSubject[T], pred: (T,int) -> bool): bool =
  var index = -1
  for i, item in self.values.pairs():
    if pred(item, i):
      index = i
      break
  if index >= self.values.len or index < 0:
    return false

  let item = self.values[index]
  self.values.delete(index)
  result = true

  # NOTE: Copying the subscriber list because the subscriber list might change while we're iiterating
  let subs = self.subscribers
  for subscriber in subs:
    subscriber.onChanged(
      Change[T](
        kind: ChangeKind.Removed,
        removedItem: item,
        removedFromIndex: index
      )
    )

proc clear*[T](self: CollectionSubject[T]): void =
  let values = self.values
  for v in values:
    self.remove(v)

proc set*[T](self: CollectionSubject[T], index: int, newVal: T): void =
  if index >= self.values.len:
    raise newException(Exception, "Unable to set a value outside the range of the collection")
  let oldVal = self.values[index]
  self.values[index] = newVal

  # NOTE: Copying the subscriber list because the subscriber list might change while we're iiterating
  let subs = self.subscribers
  for subscriber in subs:
    subscriber.onChanged(
      Change[T](
        kind: ChangeKind.Changed,
        changedAtIndex: index,
        oldVal: oldVal,
        newVal: newVal,
      )
    )

template `[]=`*[T](self: CollectionSubject[T], index: int, newVal: T): void =
  self.set(index, newVal)

proc asObservableCollection*[T](values: seq[Observable[T]]): CollectionSubject[T] =
  let res = observableCollection[T]()
  values.apply(
    proc(val: Observable[T]): void =
      var prevVal: T = nil
      # TODO: Handle this subscription somehow
      discard val.subscribe(
        proc(newVal: T): void =
          if not isNil(prevVal):
            res.remove(prevVal)
          prevVal = newVal
          res.add(newVal)
      )
  )
  res

# NOTE: HACK
proc cache*[T](self: ObservableCollection[T]): CollectionSubject[T] =
  let subject = observableCollection[T]()
  discard self.subscribe(
    proc(change: Change[T]): void =
      case change.kind:
        of ChangeKind.Added:
          subject.insert(change.newItem, change.addedAtIndex)
        of ChangeKind.Removed:
          subject.removeAt(change.removedFromIndex)
        of ChangeKind.Changed:
          subject.set(change.changedAtIndex, change.newVal)
        of ChangeKind.InitialItems:
          for i in change.items:
            subject.add(i)
  )
  subject


proc subscribe*[T](self: ObservableCollection[T], subscriber: CollectionSubscriber[T]): Subscription =
  self.onSubscribe(subscriber)

template subscribe*[T](self: CollectionSubject[T], subscriber: CollectionSubscriber[T]): Subscription =
  self.source.subscribe(subscriber)


proc subscribe*[T](self: ObservableCollection[T], onChanged: Change[T] -> void): Subscription =
  self.onSubscribe(CollectionSubscriber[T](
    onChanged: onChanged
  ))

template subscribe*[T](self: CollectionSubject[T], onChanged: Change[T] -> void): Subscription =
  self.source.subscribe(onChanged)

proc subscribe*[T](self: ObservableCollection[T], onAdded: T -> void, onRemoved: T -> void): Subscription =
  self.onSubscribe(CollectionSubscriber[T](
    onChanged: proc(change: Change[T]): void =
      case change.kind:
        of ChangeKind.Added:
          onAdded(change.newItem)
        of ChangeKind.Removed:
          onRemoved(change.removedItem)
        else:
          discard
  ))

proc subscribe*[T](self: ObservableCollection[T], onAdded: T -> void, onRemoved: T -> void, initialItems: seq[T] -> void): Subscription =
  self.onSubscribe(CollectionSubscriber[T](
    onChanged: proc(change: Change[T]): void =
      case change.kind:
        of ChangeKind.Added:
          onAdded(change.newItem)
        of ChangeKind.Removed:
          onRemoved(change.removedItem)
        of ChangeKind.InitialItems:
          initialItems(change.items)
        else:
          discard
  ))

proc subscribe*[T](self: CollectionSubject[T], onAdded: T -> void, onRemoved: T -> void): Subscription =
  self.source.subscribe(onAdded, onRemoved)

proc subscribe*[T](self: CollectionSubject[T], onAdded: T -> void, onRemoved: T -> void, initialItems: seq[T] -> void): Subscription =
  self.source.subscribe(onAdded, onRemoved, initialItems)

proc contains*[T](self: CollectionSubject[T], item: T): Observable[bool] =
  createObservable(
    proc(subscriber: Subscriber[bool]): Subscription =
      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          subscriber.onNext(item in self.values)
      )
      subscriber.onNext(item in self.values)
      # TODO: Handle subscriptions for observable collection
      Subscription(
        dispose: subscription.dispose
      )
  )

# TODO: Implement contains for ObservableCollection
# proc contains*[T](self: ObservableCollection[T], item: T): Observable[bool] =
#   self.source.contains(item)

proc len*[T](self: CollectionSubject[T]): Observable[int] =
  createObservable(
    proc(subscriber: Subscriber[int]): Subscription =
      subscriber.onNext(self.values.len())
      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          subscriber.onNext(self.values.len())
      )
      # TODO: Handle subscriptions for observable collection
      Subscription(
        dispose: subscription.dispose
      )
  )

proc len*[T](self: ObservableCollection[T]): Observable[int] =
  createObservable(
    proc(subscriber: Subscriber[int]): Subscription =
      var collectionLength = 0
      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          case change.kind:
            of ChangeKind.Added:
              collectionLength += 1
            of ChangeKind.Removed:
              collectionLength -= 1
            of ChangeKind.Changed:
              discard
            of ChangeKind.InitialItems:
              collectionLength = change.items.len
          subscriber.onNext(collectionLength)
      )
      # TODO: Handle subscriptions for observable collection
      Subscription(
        dispose: subscription.dispose
      )
  )

proc map*[T,R](self: ObservableCollection[T], mapper: (T, int) -> R): ObservableCollection[R] =
  ## Maps items using the supplied mapper function. T must have hash implemented in order for this operator
  ## to work properly.
  var mapped = initTable[T,R]()
  ObservableCollection[R](
    onSubscribe: proc(subscriber: CollectionSubscriber[R]): Subscription =
      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          case change.kind:
            of ChangeKind.Added:
              let res = mapper(change.newItem, change.addedAtIndex)
              mapped[change.newItem] = res
              subscriber.onChanged(Change[R](
                kind: ChangeKind.Added,
                newItem: res,
                addedAtIndex: change.addedAtIndex
              ))
            of ChangeKind.Removed:
              let mappedItem = mapped[change.removedItem]
              subscriber.onChanged(Change[R](
                kind: ChangeKind.Removed,
                removedItem: mappedItem,
                removedFromIndex: change.removedFromIndex
              ))
            of ChangeKind.Changed:
              let newMappedVal = mapper(change.newVal, change.changedAtIndex)
              mapped[change.newVal] = newMappedVal
              subscriber.onChanged(Change[R](
                kind: ChangeKind.Changed,
                newVal: newMappedVal,
                changedAtIndex: change.changedAtIndex
              ))
            of ChangeKind.InitialItems:
              var mappedItems: seq[R] = @[]
              for index, i in change.items.pairs():
                let mappedItem = mapper(i, index)
                mapped[i] = mappedItem
                mappedItems.add(mappedItem)
              subscriber.onChanged(Change[R](
                kind: ChangeKind.InitialItems,
                items: mappedItems
              ))
      )
      Subscription(
        dispose: subscription.dispose
      )
  )

proc map*[T,R](self: CollectionSubject[T], mapper: (T, int) -> R): ObservableCollection[R] =
  self.source.mapIndex(mapper)


proc map*[T,R](self: ObservableCollection[T], mapper: (T) -> R): ObservableCollection[R] =
  self.map(
    (item: T, index: int) => mapper(item)
  )

proc map*[T,R](self: CollectionSubject[T], mapper: (T) -> R): ObservableCollection[R] =
  self.source.map(mapper)

proc filter*[T](self: ObservableCollection[T], predicate: T -> bool): ObservableCollection[T] =
  ObservableCollection[T](
    onSubscribe: proc(subscriber: CollectionSubscriber[T]): Subscription =
      var items: seq[T] = @[]
      proc calculateActualIndex(index: int): int =
        var i = 0
        for (originalIndex, item) in items.pairs():
          if originalIndex == index:
            return i
          if predicate(item):
            i += 1
        raise newException(Exception, "Failed to calculate index during filtering of observable collection")

      proc collectionLen(): int =
        for (originalIndex, item) in items.pairs():
          if predicate(item):
            result += 1

      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          case change.kind:
            of ChangeKind.Added:
              items.insert(change.newItem, change.addedAtIndex)
              if predicate(change.newItem):
                subscriber.onChanged(Change[T](
                  kind: ChangeKind.Added,
                  newItem: change.newItem,
                  addedAtIndex: calculateActualIndex(change.addedAtIndex)
                ))
            of ChangeKind.Removed:
              if predicate(change.removedItem):
                subscriber.onChanged(Change[T](
                  kind: ChangeKind.Removed,
                  removedItem: change.removedItem,
                  removedFromIndex: calculateActualIndex(change.removedFromIndex)
                ))
              items.delete(change.removedFromIndex)
            of ChangeKind.Changed:
              items[change.changedAtIndex] = change.newVal
              if predicate(change.newVal) and not predicate(change.oldVal):
                subscriber.onChanged(Change[T](
                  kind: ChangeKind.Added,
                  newItem: change.newVal,
                  addedAtIndex: calculateActualIndex(change.changedAtIndex)
                ))
              elif not predicate(change.newVal) and predicate(change.oldVal):
                subscriber.onChanged(Change[T](
                  kind: ChangeKind.Removed,
                  removedItem: change.oldVal,
                  removedFromIndex: calculateActualIndex(change.changedAtIndex)
                ))
              elif predicate(change.newVal) and predicate(change.oldVal):
                subscriber.onChanged(Change[T](
                  kind: ChangeKind.Changed,
                  oldVal: change.oldVal,
                  newVal: change.newVal,
                  changedAtIndex: calculateActualIndex(change.changedAtIndex)
                ))
            of ChangeKind.InitialItems:
              var actualIndex = 0
              for (index, item) in change.items.pairs():
                items.add(item)
                if predicate(item):
                  subscriber.onChanged(Change[T](
                    kind: ChangeKind.Added,
                    newItem: item,
                    addedAtIndex: actualIndex
                  ))
                  actualIndex += 1
      )
      Subscription(
        dispose: subscription.dispose
      )
  )

template filter*[T](self: CollectionSubject[T], predicate: T -> bool): ObservableCollection[T] =
  self.source.filter(predicate)

proc toObservable*[T](self: CollectionSubject[T]): Observable[seq[T]] =
  createObservable(
    proc(subscriber: Subscriber[seq[T]]): Subscription =
      subscriber.onNext(self.values)
      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          let valuesCopy = self.values
          subscriber.onNext(valuesCopy)
      )
      Subscription(
        dispose: subscription.dispose
      )
  )

proc toObservable*[T](self: ObservableCollection[T]): Observable[seq[T]] =
  var valuesCache: seq[T] = @[]
  createObservable(
    proc(subscriber: Subscriber[seq[T]]): Subscription =
      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          case change.kind:
            of ChangeKind.Added:
              valuesCache.insert(change.newItem, change.addedAtIndex)
            of ChangeKind.Removed:
              valuesCache.delete(change.removedFromIndex)
            of ChangeKind.Changed:
              valuesCache[change.changedAtIndex] = change.newVal
            of ChangeKind.InitialItems:
              valuesCache = change.items
          subscriber.onNext(valuesCache)
      )
      Subscription(
        dispose: subscription.dispose
      )
  )

# TODO: Find a better name for this
proc observableCollection*[T](source: ObservableCollection[T]): CollectionSubject[T] =
  ## Wraps an ObservableCollection[T] in a CollectionSubject[T] so that its items are
  ## synchronously available.
  let subject = CollectionSubject[T]()
  subject.source = ObservableCollection[T](
    onSubscribe: proc(subscriber: CollectionSubscriber[T]): Subscription =
      let subscription = source.subscribe(
        proc(change: Change[T]): void =
          case change.kind:
            of ChangeKind.Added:
              subject.add(change.newItem)
            of ChangeKind.Removed:
              subject.remove(change.removedItem)
            of ChangeKind.InitialItems:
              subject.values = change.items
              subscriber.onChanged(
                change
              )
            else:
              # TODO: Support rest of changes
              discard
      )

      Subscription(
        dispose: subscription.dispose
      )
  )
  subject


proc combineLatest*[A,B,R](a: ObservableCollection[A], b: ObservableCollection[B], mapper: (A,B) -> R): ObservableCollection[R] =
  ObservableCollection(
    onSubscribe: proc(subscriber: CollectionSubscriber[R]): Subscription =
      var lastAddedA: A
      var lastAddedB: B

      var lastRemovedA: A
      var lastRemovedB: B

      var initialItemsA: seq[A]
      var initialItemsB: seq[B]
      let subscriptionA = a.subscribe(
        proc(newA: A): void =
          lastAddedA = newA
          if not isNil(newA) and not isNil(lastAddedB):
            subscriber.onAdded(mapper(newA, lastAddedB)),
        proc(removedA: A): void =
          lastRemovedA = removedA
          if not isNil(lastRemovedB):
            subscriber.onRemoved(mapper(removedA, lastRemovedB)),
        proc(initialItems: seq[A]): void =
          initialItemsA = initialItems


      )
      let subscriptionB = b.subscribe(
        proc(newB: B): void =
          lastAddedB = newB
          if not isNil(newB) and not isNil(lastAddedA):
            subscriber.onAdded(mapper(lastAddedA, newB)),
        proc(removedB: B): void =
          lastRemovedB = removedB
          if not isNil(lastRemovedA):
            subscriber.onRemoved(mapper(lastRemovedA, removedB)),
        proc(initialItems: seq[B]): void =
          initialItemsB = initialItems
          if not isNil initialItemsA:
            if subscriber.initialItems.isSome:
              subscriber.initialItems.get()(initialItemsA.zip(initialItemsB).map((ab: (A,B)) => mapper(ab.a, ab.b)))
      )

      Subscription(
        dispose: proc(): void =
          subscriptionA.dispose()
          subscriptionB.dispose()
      )
  )

proc first*[T](self: ObservableCollection[T]): Observable[Option[T]] =
  var items: seq[T] = @[]
  Observable[Option[T]](
    onSubscribe:
      proc(subscriber: Subscriber[Option[T]]): Subscription =
        self.subscribe(
          proc(change: Change[T]): void =
            proc emit() =
              if items.len > 0:
                subscriber.onNext(some(items[0]))
              else:
                subscriber.onNext(none[T]())

            case change.kind:
              of ChangeKind.Added:
                items.insert(change.newItem, change.addedAtIndex)
                emit()
              of ChangeKind.Removed:
                items.delete(change.removedFromIndex)
                emit()
              of ChangeKind.Changed:
                items[change.changedAtIndex] = change.newVal
                emit()
              of ChangeKind.InitialItems:
                for item in change.items:
                  items.add(item)
                emit()
        )
  )

# TODO: Write tests
proc firstWhere*[T](self: ObservableCollection[T], predicate: T -> bool, label: string = ""): Observable[Option[T]] =
  type
    Box = ref object
      item: T
      isValid: bool
  var items: seq[Box] = @[]
  Observable[Option[T]](
    onSubscribe:
      proc(subscriber: Subscriber[Option[T]]): Subscription =
        self.subscribe(
          proc(change: Change[T]): void =
            proc emit(): void =
              for index, item in items:
                if item.isValid:
                  subscriber.onNext(some(item.item))
                  return
              subscriber.onNext(none[T]())

            case change.kind:
              of ChangeKind.Added:
                items.insert(Box(item: change.newItem, isValid: predicate(change.newItem)), change.addedAtIndex)
                emit()
              of ChangeKind.Removed:
                items.delete(change.removedFromIndex)
                emit()
              of ChangeKind.Changed:
                items[change.changedAtIndex].item = change.newVal
                items[change.changedAtIndex].isValid = predicate(change.newVal)
                emit()
              of ChangeKind.InitialItems:
                for item in change.items:
                  items.add(Box(item: item, isValid: predicate(item)))
                emit()
        )
  )

proc firstWhere*[T](self: CollectionSubject[T], predicate: T -> bool): Observable[Option[T]] =
  self.source.firstWhere(predicate)

proc toObservableCollection*[T](self: Observable[T]): ObservableCollection[T] =
  ## Combines two collection into one, without giving any guarantees about the ordering of their items.
  ObservableCollection[T](
    onSubscribe: proc(subscriber: CollectionSubscriber[T]): Subscription =
      var previousVal = none[T]()
      self.subscribe(
        proc(newItem: T): void =
          if previousVal.isNone:
            subscriber.onChanged(Change[T](
              kind: ChangeKind.Added,
              newItem: newItem,
              addedAtIndex: 0
            ))
          else:
            subscriber.onChanged(Change[T](
              kind: ChangeKind.Changed,
              oldVal: previousVal.get,
              newVal: newItem,
              changedAtIndex: 0
            ))
          previousVal = some(newItem)
      )
  )

proc any*[T](self: ObservableCollection[T], predicate: (T) -> bool): Observable[bool] =
  self.firstWhere(predicate).map(
    proc(x: Option[T]): bool =
      x.isSome
  )

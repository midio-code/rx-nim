import sugar, options, sequtils, tables, hashes
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

proc add*[T](self: CollectionSubject[T], item: T): void =
  let index = self.values.len
  self.values.add(item)
  for subscriber in self.subscribers:
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

  for subscriber in self.subscribers:
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

  for subscriber in self.subscribers:
    subscriber.onChanged(
      Change[T](
        kind: ChangeKind.Removed,
        removedItem: item,
        removedFromIndex: index
      )
    )


proc set*[T](self: CollectionSubject[T], index: int, newVal: T): void =
  if index >= self.values.len:
    raise newException(Exception, "Unable to set a value outside the range of the collection")
  let oldVal = self.values[index]
  self.values[index] = newVal
  for subscriber in self.subscribers:
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
          subject.add(change.newItem)
        of ChangeKind.Removed:
          subject.remove(change.removedItem)
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
          subscriber.onNext(self.values.contains(item))
      )
      subscriber.onNext(self.values.contains(item))
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

# TODO: Implement len for ObservableCollection
# proc len*[T](self: ObservableCollection[T]): Observable[int] =
#   self.source.len()

proc map*[T,R](self: ObservableCollection[T], mapper: T -> R): ObservableCollection[R] =
  ## Maps items using the supplied mapper function. T must have hash implemented in order for this operator
  ## to work properly.
  var mapped = initTable[T,R]()
  ObservableCollection[R](
    onSubscribe: proc(subscriber: CollectionSubscriber[R]): Subscription =
      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          case change.kind:
            of ChangeKind.Added:
              let res = mapper(change.newItem)
              mapped[change.newItem] = res
              subscriber.onChanged(Change[R](
                kind: ChangeKind.Added,
                newItem: res
              ))
            of ChangeKind.Removed:
              let mappedItem = mapped[change.removedItem]
              mapped.del(change.removedItem)
              subscriber.onChanged(Change[R](
                kind: ChangeKind.Removed,
                removedItem: mappedItem
              ))
            of ChangeKind.Changed:
              let newMappedVal = mapper(change.newVal)
              mapped[change.newVal] = newMappedVal
              subscriber.onChanged(Change[R](
                kind: ChangeKind.Changed,
                newVal: newMappedVal,
                changedAtIndex: change.changedAtIndex
              ))
            of ChangeKind.InitialItems:
              var mappedItems: seq[R] = @[]
              for i in change.items:
                let mappedItem = mapper(i)
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

template map*[T,R](self: CollectionSubject[T], mapper: (T) -> R): ObservableCollection[R] =
  self.source.map(mapper)

proc filter*[T](self: ObservableCollection[T], predicate: T -> bool): ObservableCollection[T] =
  ObservableCollection[T](
    onSubscribe: proc(subscriber: CollectionSubscriber[T]): Subscription =
      let subscription = self.subscribe(
        proc(newVal: T): void =
          if predicate(newVal):
            subscriber.onChanged(Change[T](
              kind: ChangeKind.Added,
              newItem: newVal
            )),
        proc(removedVal: T): void =
          if predicate(removedVal):
            subscriber.onChanged(Change[T](
              kind: ChangeKind.Removed,
              removedItem: removedVal
            )),
        proc(initialItems: seq[T]): void =
          subscriber.onChanged(Change[T](
            kind: ChangeKind.InitialItems,
            items: initialItems.filter(predicate)
          )),
        # TODO: Support the remaining change kinds
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
        proc(added: T): void =
          subscriber.onNext(self.values),
        proc(removed: T): void =
          subscriber.onNext(self.values),
        proc(initialItems: seq[T]): void =
          subscriber.onNext(initialItems)
      )
      Subscription(
        dispose: subscription.dispose
      )
  )

proc toObservable*[T](self: ObservableCollection[T]): Observable[seq[T]] =
  var values: seq[T] = @[]
  createObservable(
    proc(subscriber: Subscriber[seq[T]]): Subscription =
      let subscription = self.subscribe(
        proc(added: T): void =
          values.add(added)
          subscriber.onNext(values),
        proc(removed: T): void =
          values.delete(values.find(removed))
          subscriber.onNext(values),
        proc(initialItems: seq[T]): void =
          values = initialItems
          subscriber.onNext(values)
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


# TODO: Write tests
proc firstWhere*[T](self: ObservableCollection[T], predicate: T -> bool): Observable[Option[T]] =
  var emittedStack: seq[T] = @[]
  Observable[Option[T]](
    onSubscribe:
      proc(subscriber: Subscriber[Option[T]]): Subscription =
        self.subscribe(
          proc(added: T): void =
            if emittedStack.len > 0:
              return
            if predicate(added):
              emittedStack.add(added)
              subscriber.onNext(some(added))
              return,
          proc(removed: T): void =
            if removed in emittedStack:
              emittedStack.delete(emittedStack.find(removed))
              if emittedStack.len > 0:
                subscriber.onNext(some(emittedStack[emittedStack.len - 1]))
              else:
                subscriber.onNext(none[T]())
          ,
          proc(initial: seq[T]): void =
            for i in initial:
              if predicate(i):
                subscriber.onNext(some(i))
                emittedStack.add(i)
                return
        )
  )

proc firstWhere*[T](self: CollectionSubject[T], predicate: T -> bool): Observable[Option[T]] =
  self.source.firstWhere(predicate)

proc `&`*[T](self: ObservableCollection[T], other: ObservableCollection[T]): ObservableCollection[T] =
  ## Combines two collection into one, without giving any guarantees about the ordering of their items.
  ObservableCollection[T](
    onSubscribe: proc(subscriber: CollectionSubscriber[T]): Subscription =
      var didFireInitialItemsEvent = false
      proc handler(change: Change[T]): void =
        case change.kind:
          of ChangeKind.Added, ChangeKind.Removed:
            subscriber.onChanged(change)
          of ChangeKind.InitialItems:
            if not didFireInitialItemsEvent:
              didFireInitialItemsEvent = true
              subscriber.onChanged(change)
            else:
              for item in change.items:
                subscriber.onChanged(
                  Change[T](
                    kind: ChangeKind.Added,
                    newItem: item
                  )
                )
      self.subscribe(handler) & other.subscribe(handler)
  )

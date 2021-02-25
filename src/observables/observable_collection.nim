import sugar, options, sequtils, tables, hashes, lists
import types
import observables
import utils

proc observableCollection*[T](values: seq[T] = @[]): CollectionSubject[T] =
  var items = initDoublyLinkedList[T]()
  for v in values:
    items.append(v)
  let subject = CollectionSubject[T](
    items: items
  )
  subject.source = ObservableCollection[T](
    onSubscribe: proc(subscriber: CollectionSubscriber[T]): Subscription =
      subject.subscribers.add(subscriber)
      subscriber.onChanged(
        Change[T](
          kind: ChangeKind.InitialItems,
          items: toSeq(toSeq(subject.values))
        )
      )
      Subscription(
        dispose: proc(): void =
          subject.subscribers.delete(subject.subscribers.find(subscriber))
      )
  )
  subject

proc len[T](self: DoublyLinkedList[T]): int =
  for item in self.items():
    result += 1

proc indexOf[T](self: DoublyLinkedList[T], item: T): int =
  var index = 0
  for i in self.items():
    if i == item:
      return index
    index += 1
  return -1


proc add*[T](self: CollectionSubject[T], item: T): void =
  var index = self.items.len
  self.items.append(item)
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
  let index = self.items.indexOf(item)
  if index >= self.items.len or index < 0:
    raise newException(Exception, "Tried to remove an item that was not in the collection.")
  self.items.remove(self.items.find(item))

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
  var i = 0
  var item: T
  for node in self.items.nodes:
    if pred(node.value, i):
      index = i
      item = node.value
      self.items.remove(node)
      break
    i += 1
  if index < 0:
    return false

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

proc itemAt[T](self: DoublyLinkedList[T], index: int): T =
  var i = 0
  for item in self.items:
    if i == index:
      return item
    i += 1

proc nodeAt[T](self: DoublyLinkedList[T], index: int): DoublyLinkedNode[T] =
  var i = 0
  for item in self.nodes:
    if i == index:
      return item
    i += 1

proc set*[T](self: CollectionSubject[T], index: int, newVal: T): void =
  echo "Items:"
  for item in self.values:
    echo "   item: ", item
  echo "New val: ", newVal
  if index >= self.items.len:
    raise newException(Exception, "Unable to set a value outside the range of the collection")
  let node = self.items.nodeAt(index)
  let oldVal = node.value
  node.value = newVal

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
          subscriber.onNext(self.items.contains(item))
      )
      subscriber.onNext(self.items.contains(item))
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
      subscriber.onNext(self.items.len())
      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          subscriber.onNext(self.items.len())
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
                newItem: res,
                addedAtIndex: change.addedAtIndex
              ))
            of ChangeKind.Removed:
              let mappedItem = mapped[change.removedItem]
              mapped.del(change.removedItem)
              subscriber.onChanged(Change[R](
                kind: ChangeKind.Removed,
                removedItem: mappedItem,
                removedFromIndex: change.removedFromIndex
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
      var gaps: seq[int] = @[] # NOTE: Indices that has been filtered out
      proc calculateActualIndex(index: int): int =
        var offset = 0
        for g in gaps:
          if g < index:
            offset += 1
        assert(index - offset >= 0)
        index - offset

      var collectionLen = 0
      let subscription = self.subscribe(
        proc(change: Change[T]): void =
          case change.kind:
            of ChangeKind.Added:
              if predicate(change.newItem):
                subscriber.onChanged(Change[T](
                  kind: ChangeKind.Added,
                  newItem: change.newItem,
                  addedAtIndex: calculateActualIndex(change.addedAtIndex)
                ))
                collectionLen += 1
              else:
                gaps.add(change.addedAtIndex)
            of ChangeKind.Removed:
              if predicate(change.removedItem):
                subscriber.onChanged(Change[T](
                  kind: ChangeKind.Removed,
                  removedItem: change.removedItem,
                  removedFromIndex: calculateActualIndex(change.removedFromIndex)
                ))
                collectionLen -= 1
            of ChangeKind.Changed:
              if predicate(change.newVal):
                if not predicate(change.oldVal):
                  gaps.delete(gaps.find(change.changedAtIndex))
                let actualIndex = calculateActualIndex(change.changedAtIndex)
                if actualIndex == collectionLen:
                  subscriber.onChanged(Change[T](
                    kind: ChangeKind.Added,
                    newItem: change.newVal,
                    addedAtIndex: actualIndex
                  ))
                  collectionLen += 1
                else:
                  subscriber.onChanged(Change[T](
                    kind: ChangeKind.Changed,
                    oldVal: change.oldVal,
                    newVal: change.newVal,
                    changedAtIndex: actualIndex
                  ))
            of ChangeKind.InitialItems:
              var actualIndex = 0
              for (index, item) in change.items.pairs():
                if predicate(item):
                  subscriber.onChanged(Change[T](
                    kind: ChangeKind.Added,
                    newItem: item,
                    addedAtIndex: actualIndex
                  ))
                  collectionLen += 1
                  actualIndex += 1
                else:
                  gaps.add(index)
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
      subscriber.onNext(toSeq(self.values))
      let subscription = self.subscribe(
        proc(added: T): void =
          subscriber.onNext(toSeq(self.values)),
        proc(removed: T): void =
          subscriber.onNext(toSeq(self.values)),
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
# proc observableCollection*[T](source: ObservableCollection[T]): CollectionSubject[T] =
#   ## Wraps an ObservableCollection[T] in a CollectionSubject[T] so that its items are
#   ## synchronously available.
#   let subject = CollectionSubject[T]()
#   subject.source = ObservableCollection[T](
#     onSubscribe: proc(subscriber: CollectionSubscriber[T]): Subscription =
#       let subscription = source.subscribe(
#         proc(change: Change[T]): void =
#           case change.kind:
#             of ChangeKind.Added:
#               subject.add(change.newItem)
#             of ChangeKind.Removed:
#               subject.remove(change.removedItem)
#             of ChangeKind.InitialItems:
#               subject.values = change.items
#               subscriber.onChanged(
#                 change
#               )
#             else:
#               # TODO: Support rest of changes
#               discard
#       )

#       Subscription(
#         dispose: subscription.dispose
#       )
#   )
#   subject


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
            subscriber.onNext(none[T]())
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

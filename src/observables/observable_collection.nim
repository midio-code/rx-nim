import sugar, options, sequtils
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
      if subscriber.initialItems.isSome:
        subscriber.initialItems.get()(subject.values)
      Subscription(
        dispose: proc(): void =
          subject.subscribers.remove(subscriber)
      )
  )
  subject

proc add*[T](self: CollectionSubject[T], item: T): void =
  self.values.add(item)
  for subscriber in self.subscribers:
    subscriber.onAdded(item)

proc remove*[T](self: CollectionSubject[T], item: T): void =
  self.values.delete(self.values.find(item))
  for subscriber in self.subscribers:
    subscriber.onRemoved(item)

proc subscribe*[T](self: ObservableCollection[T], onAdded: T -> void, onRemoved: T -> void): Subscription =
  self.onSubscribe(CollectionSubscriber[T](
    onAdded: onAdded,
    onRemoved: onRemoved
  ))

proc subscribe*[T](self: ObservableCollection[T], onAdded: T -> void, onRemoved: T -> void, initialItems: seq[T] -> void): Subscription =
  self.onSubscribe(CollectionSubscriber[T](
    onAdded: onAdded,
    onRemoved: onRemoved,
    initialItems: some(initialItems)
  ))

proc subscribe*[T](self: CollectionSubject[T], onAdded: T -> void, onRemoved: T -> void): Subscription =
  self.source.subscribe(onAdded, onRemoved)

proc subscribe*[T](self: CollectionSubject[T], onAdded: T -> void, onRemoved: T -> void, initialItems: seq[T] -> void): Subscription =
  self.source.subscribe(onAdded, onRemoved, initialItems)

proc contains*[T](self: CollectionSubject[T], item: T): Observable[bool] =
  createObservable(
    proc(subscriber: Subscriber[bool]): Subscription =
      let subscription = self.subscribe(
        proc(val: T): void =
          subscriber.onNext(self.values.contains(item)),
        proc(val: T): void =
          subscriber.onNext(self.values.contains(item)),
        proc(initial: seq[T]): void =
          subscriber.onNext(self.values.contains(item)),
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
        proc(val: T): void =
          subscriber.onNext(self.values.len()),
        proc(val: T): void =
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
  ObservableCollection[R](
    onSubscribe: proc(subscriber: CollectionSubscriber[R]): Subscription =
      let subscription = self.subscribe(
        proc(newVal: T): void =
          subscriber.onAdded(mapper(newVal)),
        proc(removedVal: T): void =
          subscriber.onRemoved(mapper(removedVal)),
        proc(initialItems: seq[T]): void =
          if subscriber.initialItems.isSome:
            subscriber.initialItems.get()(initialItems.map(mapper))
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
            subscriber.onAdded(newVal),
        proc(removedVal: T): void =
          if predicate(removedVal):
            subscriber.onRemoved(removedVal),
        proc(initialItems: seq[T]): void =
          if subscriber.initialItems.isSome:
            subscriber.initialItems.get()(initialItems.filter(predicate))
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
        proc(added: T): void =
          subject.add(added),
        proc(removed: T): void =
          subject.remove(removed),
        proc(initialItems: seq[T]): void =
          subject.values = initialItems
          if subscriber.initialItems.isSome:
            subscriber.initialItems.get()(subject.values)
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

proc log*[T](self: ObservableCollection[T], prefix: string = ""): ObservableCollection[T] =
  self.map(
    proc(x: T): T =
      echo(prefix, $x)
      x
  )

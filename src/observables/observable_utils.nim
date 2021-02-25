import options, sugar, tables
import ./types
import ./observables

proc choose*[T](self: Observable[bool], onTrue: T, onFalse: T): Observable[T] =
  ## Maps to the first argument if the value of the obsevable is true, otherwise chooses the second argument.
  self.map(
    proc(x: bool): T =
      if x:
        onTrue
      else:
        onFalse
  )

proc whenTrue*[T](self: Observable[bool], onTrue: T): Observable[Option[T]] =
  self.map(
    proc(x: bool): Option[T] =
      if x:
        some(onTrue)
      else:
        none[T]()
  )

proc unwrap*[T](self: Observable[Option[T]]): Observable[T] =
  self.filter(
    proc(x: Option[T]): bool =
      x.isSome()
  ).map(
    proc(x: Option[T]): T =
      x.get()
  )

proc unwrap*[T](self: Observable[seq[Option[T]]]): Observable[seq[T]] =
  self.map(
    proc(x: seq[Option[T]]): seq[T] =
      x.filter(
        proc(o: Option[T]): bool =
          o.isSome()
      ).map(
        proc(o: Option[T]): T =
          o.get()
      )
  )

proc unwrap*[T](self: ObservableCollection[Option[T]]): ObservableCollection[T] =
  self.filter(
    proc(x: Option[T]): bool =
      x.isSome()
  ).map(
    proc(x: Option[T]): T =
      x.get()
  )


proc switch*[A](observables: Observable[ObservableCollection[A]]): ObservableCollection[A] =
  ## Subscribes to each observable as they arrive after first unsubscribing from the second,
  ## emitting their values as they arrive.
  ObservableCollection[A](
    onSubscribe: proc(subscriber: CollectionSubscriber[A]): Subscription =
      var currentSubscription: Subscription
      let outerSub = observables.subscribe(
        proc(innerObs: ObservableCollection[A]): void =
          if not isNil(currentSubscription):
            currentSubscription.dispose()
          currentSubscription = innerObs.onSubscribe(subscriber)
      )
      Subscription(
        dispose: proc(): void =
          if not isNil(currentSubscription):
            currentSubscription.dispose()
          outerSub.dispose()
      )
  )


proc switch*[A](self: ObservableCollection[Observable[A]]): ObservableCollection[A] =
  ObservableCollection[A](
    onSubscribe: proc(subscriber: CollectionSubscriber[A]): Subscription =
      var values = initTable[int, A]()
      var subscriptions = initTable[int, Subscription]()

      proc createSubscription(obs: Observable[A], forIndex: int): void =
        subscriptions[forIndex] = obs.subscribe(
          proc(val: A): void =
            if not values.hasKey(forIndex):
              subscriber.onChanged(
                Change[A](
                  kind: ChangeKind.Added,
                  newItem: val,
                  addedAtIndex: forIndex
                )
              )
            else:
              subscriber.onChanged(
                Change[A](
                  kind: ChangeKind.Changed,
                  oldVal: values[forIndex],
                  newVal: val,
                  changedAtIndex: forIndex
                )
              )
            values[forIndex] = val
        )


      let subscription = self.subscribe(
        proc(change: Change[Observable[A]]): void =
          case change.kind:
            of ChangeKind.Added:
              createSubscription(change.newItem, change.addedAtIndex)
            of ChangeKind.Removed:
              subscriber.onChanged(Change[A](
                kind: ChangeKind.Removed,
                removedItem: values[change.removedFromIndex]
              ))
              subscriptions[change.removedFromIndex].dispose()
              subscriptions.del(change.removedFromIndex)
              values.del(change.removedFromIndex)
            of ChangeKind.Changed:
              subscriptions[change.changedAtIndex].dispose()
              createSubscription(change.newVal, change.addedAtIndex)
            of ChangeKind.InitialItems:
              for (index, item) in change.items.pairs():
                createSubscription(item, index)
      )
      proc disposeAll(): void =
        subscription.dispose()
        for (index, sub) in subscriptions.pairs():
          sub.dispose()
      Subscription(
        dispose: disposeAll
      )
  )

proc switch*[A](self: ObservableCollection[ObservableCollection[A]]): ObservableCollection[A] =
  ObservableCollection[A](
    onSubscribe: proc(subscriber: CollectionSubscriber[A]): Subscription =
      var values = initTable[int, A]()
      var subscriptions = initTable[int, Subscription]()
      var collectionSizes: seq[int] = @[]
      var indexOffsets = initTable[int, int]()

      proc offsetForIndex(index: int): int =
        var ret = 0
        for (i, size) in collectionSizes.pairs():
          if i == index:
            return ret
          ret += size
      proc incrementOffsetAfterIndex(index: int) =
        for i in index..collectionSizes.len - 1:
          collectionSizes[i] += 1
      proc decrementOffsetAfterIndex(index: int) =
        for i in index..collectionSizes.len - 1:
          collectionSizes[i] -= 1

      proc createSubscription(obs: ObservableCollection[A], forIndex: int): void =
        collectionSizes.insert(0, forIndex)
        subscriptions[forIndex] = obs.subscribe(
          proc(change: Change[A]): void =
            case change.kind:
              of ChangeKind.Added:
                echo "Add for item: ", change.newItem
                subscriber.onChanged(Change[A](
                  kind: ChangeKind.Added,
                  newItem: change.newItem,
                  addedAtIndex: offsetForIndex(forIndex) + change.addedAtIndex
                ))
                echo "Foo"
                incrementOffsetAfterIndex(forIndex)
                echo "Bar"
              of ChangeKind.Removed:
                echo "Remove for item"
                subscriber.onChanged(Change[A](
                  kind: ChangeKind.Removed,
                  removedItem: change.removedItem,
                  removedFromIndex: offsetForIndex(forIndex) + change.removedFromIndex
                ))
                decrementOffsetAfterIndex(forIndex)
              of ChangeKind.Changed:
                echo "Change for index: ", forIndex, " at position: ", change.changedAtIndex, " actual pos: ", (offsetForIndex(forIndex) + change.changedAtIndex)
                subscriber.onChanged(Change[A](
                  kind: ChangeKind.Changed,
                  oldVal: change.oldVal,
                  newVal: change.newVal,
                  changedAtIndex: offsetForIndex(forIndex) + change.changedAtIndex
                ))
              of ChangeKind.InitialItems:
                echo "Initial for item"
                collectionSizes[forIndex] = change.items.len
                for (index, item) in change.items.pairs():
                  subscriber.onChanged(Change[A](
                    kind: ChangeKind.Added,
                    addedAtIndex: offsetForIndex(forIndex) + index,
                    newItem: item
                  ))
        )

      let subscription = self.subscribe(
        proc(change: Change[ObservableCollection[A]]): void =
          echo "Foo"
          case change.kind:
            of ChangeKind.Added:
              createSubscription(change.newItem, change.addedAtIndex)
            of ChangeKind.Removed:
              # TODO: Handle removal of collection in switched nested collections
              raise newException(Exception, "Removal of collection in switched nested collection is currently not supported")
              collectionSizes.delete(change.removedFromIndex)
              subscriber.onChanged(Change[A](
                kind: ChangeKind.Removed,
                removedItem: values[change.removedFromIndex]
              ))
              subscriptions[change.removedFromIndex].dispose()
              subscriptions.del(change.removedFromIndex)
              values.del(change.removedFromIndex)
            of ChangeKind.Changed:
              subscriptions[change.changedAtIndex].dispose()
              createSubscription(change.newVal, change.addedAtIndex)
            of ChangeKind.InitialItems:
              for (index, item) in change.items.pairs():
                createSubscription(item, index)
      )
      proc disposeAll(): void =
        subscription.dispose()
        for (index, sub) in subscriptions.pairs():
          sub.dispose()
      Subscription(
        dispose: disposeAll
      )
  )


proc `<-`*[T](subj: Subject[T], other: T): void =
  subj.next(other)

proc `+=`*[T](subj: Subject[T], other: T): void =
  subj.next(subj.value + other)

proc `-=`*[T](subj: Subject[T], other: T): void =
  subj.next(subj.value - other)

proc `*=`*[T](subj: Subject[T], other: T): void =
  subj.next(subj.value * other)

proc `div=`*[T](subj: Subject[T], other: T): void =
  subj.next(subj.value div other)

proc `&`*(a: Observable[string], b: Observable[string]): Observable[string] =
  a.combineLatest(
    b,
    proc(a, b: string): string = a & b
  )

proc `&`*(a: string, b: Observable[string]): Observable[string] =
  b.map(
    proc(b: string): string = a & b
  )

proc `&`*(a: Observable[string], b: string): Observable[string] =
  a.map(
    proc(a: string): string = a & b
  )

proc `&`*[T](a: Observable[seq[T]], b: Observable[seq[T]]): Observable[seq[T]] =
  a.combineLatest(
    b,
    (a,b) => a & b
  )

proc log*[T](self: Observable[T], prefix: string = ""): Observable[T] =
  self.map(
    proc(val: T): T =
      echo prefix, val
      val
  )

proc unique*[T](self: Observable[T]): Observable[T] =
  var prev = default(T)
  self.filter(
    proc(val: T): bool =
      if val != prev:
        prev = val
        true
      else:
        false
  )

proc unique*[T](self: Subject[T]): Observable[T] =
  self.source.unique()

template castTo*[T](self: Observable[T], caster: untyped): untyped =
  self.map(
    proc(x: T): auto =
      result = caster(x)
  )

template castTo*[T](self: ObservableCollection[T], caster: untyped): untyped =
  self.map(
    proc(x: T): auto =
      result = caster(x)
  )

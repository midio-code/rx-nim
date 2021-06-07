import options, sugar, tables, hashes, lists, strformat
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

template choose*[T](self: Subject[bool], onTrue: T, onFalse: T): Observable[T] =
  self.source.choose(onTrue, onFalse)

proc whenTrue*[T](self: Observable[bool], onTrue: T): Observable[Option[T]] =
  self.map(
    proc(x: bool): Option[T] =
      if x:
        some(onTrue)
      else:
        none[T]()
  )

proc whenFalse*[T](self: Observable[bool], onFalse: T): Observable[Option[T]] =
  self.map(
    proc(x: bool): Option[T] =
      if not x:
        some(onFalse)
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

proc map*[T,R](self: Observable[Option[T]], mapper: T -> R): Observable[Option[R]] =
  self.map(
    proc(val: Option[T]): Option[R] =
      if val.isSome:
        some(mapper(val.get))
      else:
        none[R]()
  )
template map*[T,R](self: Subject[Option[T]], mapper: T -> R): Observable[Option[R]] =
  subject.source.map(mapper)

proc isSome*[T](self: Observable[Option[T]]): Observable[bool] =
  self.map((x: Option[T]) => x.isSome)

proc isNone*[T](self: Observable[Option[T]]): Observable[bool] =
  self.map((x: Option[T]) => x.isNone)

proc len*[T](self: Observable[seq[T]]): Observable[int] =
  self.map((x: seq[T]) => x.len)
template len*[T](self: Subject[seq[T]]): Observable[int] =
  self.source.len

proc len*(self: Observable[string]): Observable[int] =
  self.map((x: string) => x.len)
template len*(self: Subject[string]): Observable[int] =
  self.source.len

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
      var values: seq[Option[A]] = @[]
      var subscriptions: seq[Subscription] = @[]

      proc actualIndex(index: int): int =
        var res = 0
        for i, v in values:
          if i == index:
            return res
          if v.isSome:
            res += 1
        raise newException(Exception, "Failed to calculate index in collection.switch(observable)")


      proc createSubscription(obs: Observable[A], forIndex: int): void =
        values.insert(none[A](), forIndex)
        subscriptions.insert(obs.subscribe(
          proc(val: A): void =
            if values[forIndex].isNone:
              subscriber.onChanged(
                Change[A](
                  kind: ChangeKind.Added,
                  newItem: val,
                  addedAtIndex: actualIndex(forIndex)
                )
              )
            else:
              subscriber.onChanged(
                Change[A](
                  kind: ChangeKind.Changed,
                  oldVal: values[forIndex].get,
                  newVal: val,
                  changedAtIndex: actualIndex(forIndex)
                )
              )

            values[forIndex] = some(val)
        ), forIndex)


      let subscription = self.subscribe(
        proc(change: Change[Observable[A]]): void =
          case change.kind:
            of ChangeKind.Added:
              createSubscription(change.newItem, change.addedAtIndex)
            of ChangeKind.Removed:
              subscriber.onChanged(Change[A](
                kind: ChangeKind.Removed,
                removedItem: values[change.removedFromIndex].get,
                removedFromIndex: actualIndex(change.removedFromIndex)
              ))
              subscriptions[change.removedFromIndex].dispose()
              subscriptions.delete(change.removedFromIndex)
              values.delete(change.removedFromIndex)
            of ChangeKind.Changed:
              if subscriptions.len > change.changedAtIndex:
                subscriptions[change.changedAtIndex].dispose()
              createSubscription(change.newVal, change.changedAtIndex)
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


type Sublist[A] = ref object
  id: int
  obs: ObservableCollection[A]
  length: int

proc `$`*[A](self: Sublist[A]): string =
  &"Sublist({self.id}, {self.length})"

proc hash*[A](self: Sublist[A]): Hash =
  self.id.hash

proc `==`*[A](self: Sublist[A], other: Sublist[A]): bool =
  self.id == other.id

var sublistIdCounter = 0
proc initSublist[A](obs: ObservableCollection[A]): Sublist[A] =
  result = Sublist[A](
    id: sublistIdCounter,
    obs: obs,
    length: 0
  )
  sublistIdCounter += 1

proc switch*[A](self: ObservableCollection[ObservableCollection[A]]): ObservableCollection[A] =
  type
    SubInfo = ref object
      subscription: Subscription
      length: int
      items: seq[A]
  ObservableCollection[A](
    onSubscribe: proc(subscriber: CollectionSubscriber[A]): Subscription =
      var innerSubscriptions: seq[SubInfo] = @[]

      proc indexOffset(subInfo: SubInfo): int =
        for si in innerSubscriptions:
          if si == subInfo:
            return result
          result += si.length
      proc createSubscriptionForCollection(index: int, collection: ObservableCollection[A]): void =
        let subInfo = SubInfo(
          length: 0,
          items: @[]
        )
        innerSubscriptions.insert(subInfo, index)
        subInfo.subscription = collection.subscribe(
          proc(change: Change[A]): void =
            case change.kind:
              of ChangeKind.Added:
                subInfo.length += 1
                subInfo.items.insert(change.newItem, change.addedAtIndex)
                subscriber.onChanged(
                  Change[A](
                    kind: ChangeKind.Added,
                    addedAtIndex: subInfo.indexOffset() + change.addedAtIndex,
                    newItem: change.newItem
                  )
                )
              of ChangeKind.Removed:
                subInfo.items.delete(change.removedFromIndex)
                subInfo.length -= 1
                subscriber.onChanged(
                  Change[A](
                    kind: ChangeKind.Removed,
                    removedFromIndex: subInfo.indexOffset() + change.removedFromIndex,
                    removedItem: change.removedItem
                  )
                )
              of ChangeKind.Changed:
                subInfo.items[change.changedAtIndex] = change.newVal
                subscriber.onChanged(
                  Change[A](
                    kind: ChangeKind.Changed,
                    changedAtIndex: subInfo.indexOffset() + change.changedAtIndex,
                    oldVal: change.oldVal,
                    newVal: change.newVal
                  )
                )
              of ChangeKind.InitialItems:
                for index, item in change.items:
                  subInfo.items.add(item)
                  subscriber.onChanged(
                    Change[A](
                      kind: ChangeKind.Added,
                      addedAtIndex: subInfo.indexOffset() + subInfo.length,
                      newItem: item
                    )
                  )
                  subInfo.length += 1
        )

      proc disposeSubscription(index: int, removedItem: ObservableCollection[A]): void =
        let subInfo = innerSubscriptions[index]
        let indexOffset = subInfo.indexOffset()
        for item in subInfo.items:
          subscriber.onChanged(
            Change[A](
              kind: ChangeKind.Removed,
              removedFromIndex: indexOffset,
              removedItem: item
            )
          )
        subInfo.subscription.dispose()
        innerSubscriptions.delete(index)

      let subscription = self.subscribe(
        proc(change: Change[ObservableCollection[A]]): void =
          case change.kind:
            of ChangeKind.Added:
              createSubscriptionForCollection(change.addedAtIndex, change.newItem)
            of ChangeKind.Removed:
              disposeSubscription(change.removedFromIndex, change.removedItem)
            of ChangeKind.Changed:
              disposeSubscription(change.changedAtIndex, change.oldVal)
              createSubscriptionForCollection(change.changedAtIndex, change.newVal)
            of ChangeKind.InitialItems:
              for (index, initialItem) in change.items.pairs():
                createSubscriptionForCollection(index, initialItem)
      )
      proc disposeAll(): void =
        subscription.dispose()
        for subInfo in innerSubscriptions:
          subInfo.subscription.dispose()
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

proc `[]`*(a: Observable[string], index: int): Observable[string] =
  a.map(
    proc(a: string): string = $a[index]
  )
template `[]`*(a: Subject[string], index: int): Observable[string] =
  a.source[index]

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

proc log*[A](self: ObservableCollection[A], prefix: string = ""): ObservableCollection[A] =
  ObservableCollection[A](
    onSubscribe: proc(subscriber: CollectionSubscriber[A]): Subscription =
      let subscription = self.subscribe(
        proc(change: Change[A]): void =
          echo prefix, change
          subscriber.onChanged(change)
      )

      Subscription(
        dispose: subscription.dispose
      )
  )

template unique*[T](self: Observable[T]): Observable[T] =
  self.distinctUntilChanged()

template unique*[T](self: Subject[T]): Observable[T] =
  self.source.distinctUntilChanged()

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

proc `or`*(self: Observable[bool], other: Observable[bool]): Observable[bool] =
  self.combineLatest(other, (a: bool, b: bool) => a or b)

proc `and`*(self: Observable[bool], other: Observable[bool]): Observable[bool] =
  self.combineLatest(other, (a: bool, b: bool) => a and b)

proc `not`*(self: Observable[bool]): Observable[bool] =
  self.map((x: bool) => not x)

proc once*[T](self: Observable[T], handler: (T) -> void): void =
  var subscription: Subscription
  var shouldUnsubscribe = false
  subscription = self.subscribe(
    proc(val: T): void =
      handler(val)
      if not isNil(subscription):
        subscription.dispose()
      else:
        shouldUnsubscribe = true
  )
  if shouldUnsubscribe:
    subscription.dispose()

proc `+`*[T](self: Observable[T], other: Observable[T]): Observable[T] =
  self.combineLatest(other, (a, b: T) => a + b)

proc `-`*[T](self: Observable[T], other: Observable[T]): Observable[T] =
  self.combineLatest(other, (a, b: T) => a - b)

proc `/`*[T](self: Observable[T], other: Observable[T]): Observable[T] =
  self.combineLatest(other, (a, b: T) => a / b)

proc `*`*[T](self: Observable[T], other: Observable[T]): Observable[T] =
  self.combineLatest(other, (a, b: T) => a * b)

proc `>`*[T](self: Observable[T], other: Observable[T]): Observable[bool] =
  self.combineLatest(other, (a, b: T) => a > b)

proc `>=`*[T](self: Observable[T], other: Observable[T]): Observable[bool] =
  self.combineLatest(other, (a, b: T) => a >= b)

proc `<`*[T](self: Observable[T], other: Observable[T]): Observable[bool] =
  self.combineLatest(other, (a, b: T) => a < b)

proc `<=`*[T](self: Observable[T], other: Observable[T]): Observable[bool] =
  self.combineLatest(other, (a, b: T) => a <= b)

# NOTE: Avoiding an observable == operator as it is expected to return a bool,
# which a lot of std library features depend on.
proc equals*[T](self: Observable[T], other: Observable[T]): Observable[bool] =
  self.combineLatest(other, (a, b: T) => a == b)


proc `+`*[T](self: Observable[T], other: T): Observable[T] =
  self.map((x: T) => x + other)

proc `-`*[T](self: Observable[T], other: T): Observable[T] =
  self.map((x: T) => x - other)

proc `/`*[T](self: Observable[T], other: T): Observable[T] =
  self.map((x: T) => x / other)

proc `*`*[T](self: Observable[T], other: T): Observable[T] =
  self.map((x: T) => x * other)

proc `>`*[T](self: Observable[T], other: T): Observable[bool] =
  self.map((x: T) => x > other)

proc `>=`*[T](self: Observable[T], other: T): Observable[bool] =
  self.map((x: T) => x >= other)

proc `<`*[T](self: Observable[T], other: T): Observable[bool] =
  self.map((x: T) => x < other)

proc `<=`*[T](self: Observable[T], other: T): Observable[bool] =
  self.map((x: T) => x <= other)

proc equals*[T](self: Observable[T], other: T): Observable[bool] =
  self.map((x: T) => x == other)


proc debounce*[T](self: Observable[T], waitMs: int, setTimeout: (() -> void, int) -> (() -> void)): Observable[T] =
  createObservable(
    proc(subscriber: Subscriber[T]): Subscription =
      var timeout: () -> void
      let subscription = self.subscribe(
        proc(newVal: T): void =
          if not isNil(timeout):
            timeout()
          timeout = setTimeout(
            proc() =
              subscriber.onNext(newVal),
            waitMs
          )
      )
  )

proc throttle*[T](self: Observable[T], waitMs: int, setTimeout: (() -> void, int) -> (() -> void)): Observable[T] =
  createObservable(
    proc(subscriber: Subscriber[T]): Subscription =
      var canFire = true
      var fireLatestValue: () -> void
      let subscription = self.subscribe(
        proc(newVal: T): void =
          fireLatestValue = proc() =
            subscriber.onNext(newVal)

          proc fire() =
            if not isNil(fireLatestValue):
              fireLatestValue()
              fireLatestValue = nil
              canFire = false
              discard setTimeout(
                fire,
                waitMs
              )
            else:
              canFire = true

          if canFire:
            fire()
      )
  )

when defined(js):
  from dom import setTimeout, clearTimeout
  proc debounce*[T](self: Observable[T], waitMs: int): Observable[T] =
    debounce(
      self,
      waitMs,
      proc(handler: () -> void, waitMs: int): (() -> void) =
        let timeout = setTimeout(handler, waitMs)
        return proc() =
          timeout.clearTimeout
    )

  proc throttle*[T](self: Observable[T], waitMs: int): Observable[T] =
    throttle(
      self,
      waitMs,
      proc(handler: () -> void, waitMs: int): (() -> void) =
        let timeout = setTimeout(handler, waitMs)
        return proc() =
          timeout.clearTimeout
    )

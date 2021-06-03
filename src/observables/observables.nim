import options
import sugar
import types
import utils
import strformat

proc toSubscriber[T](onNext: (T) -> void): Subscriber[T] =
  Subscriber[T](onNext: onNext, onCompleted: none[() -> void](), onError: none[(Error) -> void]())

proc subscribe*[T](self: Observable[T], subscriber: Subscriber[T]): Subscription =
  assert(not isNil(self))
  self.onSubscribe(subscriber)

proc subscribe*[T](self: Subject[T], subscriber: Subscriber[T]): Subscription =
  assert(not isNil(self))
  self.source.onSubscribe(subscriber)

proc subscribe*[T](self: Observable[T], onNext: (T) -> void): Subscription =
  assert(not isNil(self))
  self.onSubscribe(toSubscriber(onNext))

proc subscribe*[T](self: Observable[T], onNext: (T) -> void, onCompleted: () -> void): Subscription =
  assert(not isNil(self))
  self.onSubscribe(Subscriber[T](onNext: onNext, onCompleted: some(onCompleted), onError: none[(Error) -> void]()))

proc subscribe*[T](self: Observable[T], onNext: (T) -> void, onCompleted: Option[() -> void], onError: Option[(Error) -> void]): Subscription =
  assert(not isNil(self))
  self.onSubscribe(Subscriber[T](onNext: onNext, onCompleted: onCompleted, onError: onError))

proc subscribe*[T](self: Subject[T], onNext: (T) -> void): Subscription =
  assert(not isNil(self))
  self.source.subscribe(onNext)

proc notifySubscribers*[T](self: Subject[T]): void =
  var disposedSubscribers: seq[Subscriber[T]] = @[]
  let subscribers = self.subscribers
  for subscriber in subscribers:
    if subscriber.disposed:
      disposedSubscribers.add(subscriber)
    else:
      subscriber.onNext(self.value)
  for subscriber in disposedSubscribers:
    self.subscribers.remove(subscriber)

proc behaviorSubject*[T](value: T = default(T)): Subject[T] =
  ## Creates a ``behaviorSubject`` with the initial value of ``value``. Behavior subjects notifies
  ## as soon as a subscription is created.
  let ret = Subject[T](
    value: value,
    didComplete: false
  )
  ret.source = Observable[T](
    onSubscribe: proc(subscriber: Subscriber[T]): Subscription =
      ret.subscribers.add(subscriber)
      subscriber.onNext(ret.value)
      Subscription(
        dispose: proc(): void =
          subscriber.disposed = true
      )
  )
  ret

proc subject*[T](): Subject[T] =
  ## Creates a normal ``subject``, which has no value, and only notifies their subscriber
  ## the next time a new value is pushed to it.
  let ret = Subject[T]()
  ret.source = Observable[T](
    onSubscribe: proc(subscriber: Subscriber[T]): Subscription =
      ret.subscribers.add(subscriber)
      Subscription(
        dispose: proc(): void =
          subscriber.disposed = true
      )
  )
  ret

template state*[T](value: T): untyped =
  behaviorSubject(value)

proc constantSubject*[T](value: T): Subject[T] =
  ## Creates a ``behaviorSubject`` with the initial value of ``value``. Behavior subjects notifies
  ## as soon as a subscription is created.
  Subject[T](
    didComplete: false,
    source: Observable[T](
    onSubscribe: proc(subscriber: Subscriber[T]): Subscription =
      subscriber.onNext(value)
      Subscription(
        proc() = discard
      )
    )
  )

proc createObservable*[T](onSubscribe: (Subscriber[T]) -> Subscription): Observable[T] =
  Observable[T](onSubscribe: onSubscribe)


proc createObservable*[T](values: seq[T]): Observable[T] =
  createObservable(
    proc(subscriber: Subscriber[T]): Subscription =
      for value in values:
        subscriber.onNext(value)
      if subscriber.onCompleted.isSome():
        subscriber.onCompleted.get()()
      Subscription(
        dispose: proc(): void = discard
      )
  )

proc then*[T](first: Observable[T], second: Observable[T]): Observable[T] =
  var currentSub: Subscription
  createObservable(
    proc(subscriber: Subscriber[T]): Subscription =
      currentSub =  first.subscribe(
        Subscriber[T](
          onNext: subscriber.onNext,
          onCompleted: some(proc(): void =
            currentSub = second.subscribe(
              Subscriber[T](onNext: subscriber.onNext, onCompleted: subscriber.onCompleted, onError: subscriber.onError)
            )
          ),
          onError: subscriber.onError
        )
      )
      Subscription(
        dispose: proc(): void =
          currentSub.dispose()
      )
    )

proc behaviorSubject*[T](source: Observable[T], defaultVal: T = default(T)): Subject[T] =
  ## Creates a ``behaviorSubject`` from another ``observable``. This is useful
  ## when one has an observable which one would like to use as a value, exposing the latest
  ## value through the subjects ``.value`` field.
  let ret = behaviorSubject[T](defaultVal)
  # NOTE: We do not care about this subscription,
  # as it is valid as long as this subject exists.
  # TODO: We might need to handle the case when the object is disposed though.
  discard source.subscribe(
    proc(newVal: T): void =
      ret.next(newVal)
  )
  ret

proc complete*[T](self: Subject[T]): void =
  self.didComplete = true
  for subscriber in self.subscribers:
    if subscriber.onCompleted.isSome():
      subscriber.onCompleted.get()()
  self.subscribers = @[]

proc next*[T](self: Subject[T], newVal: T): void =
  ## Used to push a new value to the subject, causing it to notify all its subscribers/observers.

  if self.didComplete == true:
    raise newException(Exception, "Tried to push a new value to a completed subject")
  self.value = newVal
  self.notifySubscribers()

proc next*[T](self: Subject[T], transformer: T -> T): void =
  ## Used to push a new value to the subject, causing it to notify all its subscribers/observers.
  ## This overload is useful if one wants to transform the current ``value`` using some mapping function.
  self.next(transformer(self.value))

# Operators
proc map*[T,R](self: Observable[T], mapper: T -> R): Observable[R] =
  ## Returns a new ``Observable`` which maps values from the source ``Observable`` to a new type and value.
  result = Observable[R](
    onSubscribe: proc(subscriber: Subscriber[R]): Subscription =
      self.subscribe(
        proc(newVal: T): void =
          subscriber.onNext(mapper(newVal))
      )

  )
template map*[T,R](self: Subject[T], mapper: T -> R): Observable[R] =
  self.source.map(mapper)

template extract*[T](self: Observable[T], prop: untyped): untyped =
  self.map(
    proc(val: T): auto =
      val.`prop`
  )
template extract*[T](self: Subject[T], prop: untyped): untyped =
  self.source.extract(prop)

proc filter*[T](self: Observable[T], predicate: (T) -> bool): Observable[T] =
  Observable[T](
    onSubscribe: proc(subscriber: Subscriber[T]): Subscription =
      self.subscribe(
        proc(newVal: T): void =
          if predicate(newVal):
            subscriber.onNext(newVal),
        subscriber.onCompleted,
        subscriber.onError
      )
  )

proc combineLatest*[A,B,R](a: Observable[A], b: Observable[B], mapper: (A,B) -> R): Observable[R] =
  ## Combines two observables, pushing both their values through a mapper function that maps to a new Observable type. The new observable triggers when **either** A or B changes.
  result = Observable[R](
    onSubscribe: proc(subscriber: Subscriber[R]): Subscription =
      assert(not isNil(a))
      assert(not isNil(b))
      var lastA: Option[A]
      var lastB: Option[B]
      let sub1 = a.subscribe(
        proc(newA: A): void =
          lastA = some(newA)
          if lastB.isSome():
            subscriber.onNext(mapper(newA, lastB.get()))
      )
      let sub2 = b.subscribe(
        proc(newB: B): void =
          lastB = some(newB)
          if lastA.isSome():
            subscriber.onNext(mapper(lastA.get(), newB))
      )
      Subscription(
        dispose: proc(): void =
          sub1.dispose()
          sub2.dispose()
      )
  )

proc combineLatest*[A,B,C,R](a: Observable[A], b: Observable[B], c: Observable[C], mapper: (A,B,C) -> R): Observable[R] =
  ## Combines three observables, pushing their values through a mapper function that maps to a new Observable type. The new observable triggers when **either** A, B or C changes.
  result = Observable[R](
    onSubscribe: proc(subscriber: Subscriber[R]): Subscription =
      assert(not isNil(a))
      assert(not isNil(b))
      assert(not isNil(c))
      var lastA: Option[A]
      var lastB: Option[B]
      var lastC: Option[C]
      let sub1 = a.subscribe(
        proc(newA: A): void =
          lastA = some(newA)
          if lastB.isSome() and lastC.isSome():
            subscriber.onNext(mapper(newA, lastB.get(), lastC.get()))
      )
      let sub2 = b.subscribe(
        proc(newB: B): void =
          lastB = some(newB)
          if lastA.isSome() and lastC.isSome():
            subscriber.onNext(mapper(lastA.get(), newB, lastC.get()))
      )
      let sub3 = c.subscribe(
        proc(newC: C): void =
          lastC = some(newC)
          if lastA.isSome() and lastB.isSome():
            subscriber.onNext(mapper(lastA.get(), lastB.get(), newC))
      )
      Subscription(
        dispose: proc(): void =
          sub1.dispose()
          sub2.dispose()
          sub3.dispose()
      )
  )


# TODO: Optimize
proc combineLatest*[A,B,C,D,R](
  a: Observable[A],
  b: Observable[B],
  c: Observable[C],
  d: Observable[D],
  mapper: (A,B,C,D) -> R
): Observable[R] =
    let comb1 = a.combineLatest(
      b,
      proc(aVal: A, bVal: B): (A,B) =
        (aVal, bVal)
    )
    let comb2 = c.combineLatest(
      d,
      proc(cVal: C, dVal: D): (C,D) =
        (cVal, dVal)
    )
    comb1.combineLatest(
      comb2,
      proc(left: (A,B), right: (C,D)): R =
        mapper(left[0], left[1], right[0], right[1])
    )

# TODO: Optimize
proc combineLatest*[A,B,C,D,E,R](
  a: Observable[A],
  b: Observable[B],
  c: Observable[C],
  d: Observable[D],
  e: Observable[E],
  mapper: (A,B,C,D,E) -> R
): Observable[R] =
    let comb1 = a.combineLatest(
      b,
      proc(aVal: A, bVal: B): (A,B) =
        (aVal, bVal)
    )
    let comb2 = c.combineLatest(
      d,
      proc(cVal: C, dVal: D): (C,D) =
        (cVal, dVal)
    )
    comb1.combineLatest(
      comb2,
      e,
      proc(left: (A,B), right: (C,D), e: E): R =
        mapper(left[0], left[1], right[0], right[1], e)
    )


proc merge*[A](a: Observable[A], b: Observable[A]): Observable[A] =
  ## Combines two observables. The new observable triggers when **either** A or B changes.
  Observable[A](
    onSubscribe: proc(subscriber: Subscriber[A]): Subscription =
      let sub1 = a.subscribe(
        proc(newA: A): void =
          subscriber.onNext(newA)
      )
      let sub2 = b.subscribe(
        proc(newB: A): void =
          subscriber.onNext(newB)
      )
      Subscription(
        dispose: proc(): void =
          sub1.dispose()
          sub2.dispose()
      )
  )

proc merge*[A](observables: Observable[Observable[A]]): Observable[A] =
  ## Subscribes to each observable as they arrive, emitting their values as they are emitted.
  Observable[A](
    onSubscribe: proc(subscriber: Subscriber[A]): Subscription =
      var subscriptions: seq[Subscription] = @[]
      let outerSub = observables.subscribe(
        proc(innerObs: Observable[A]): void =
          subscriptions.add innerObs.subscribe(
            proc(val: A): void =
              subscriber.onNext(val)
          )
      )
      Subscription(
        dispose: proc(): void =
          for s in subscriptions:
            s.dispose()
          outerSub.dispose()
      )
  )

proc switch*[A](observables: Observable[Observable[A]]): Observable[A] =
  ## Subscribes to each observable as they arrive after first unsubscribing from the second,
  ## emitting their values as they arrive.
  Observable[A](
    onSubscribe: proc(subscriber: Subscriber[A]): Subscription =
      var currentSubscription: Subscription
      let outerSub = observables.subscribe(
        proc(innerObs: Observable[A]): void =
          if not isNil(currentSubscription):
            currentSubscription.dispose()
          currentSubscription = innerObs.subscribe(
            proc(val: A): void =
              subscriber.onNext(val)
          )
      )
      Subscription(
        dispose: proc(): void =
          if not isNil(currentSubscription):
            currentSubscription.dispose()
          outerSub.dispose()
      )
  )

proc distinctUntilChanged*[T](self: Observable[T]): Observable[T] =
  Observable[T](
    onSubscribe: proc(subscriber: Subscriber[T]): Subscription =
      var lastVal: Option[T]
      let sub = self.subscribe(
        proc(newVal: T) =
          if lastVal.isNone or lastVal.get != newVal:
            lastVal = some(newVal)
            subscriber.onNext(newVal)
      )
      Subscription(
        dispose: proc() =
          sub.dispose()
      )
  )

template distinctUntilChanged*[T](self: Subject[T]): Observable[T] =
  self.source.distinctUntilChanged()

proc take*[T](self: Observable[T], num: int): Observable[T] =
  var counter = 0
  Observable[T](
    onSubscribe:
      proc(subscriber: Subscriber[T]): Subscription =
        var alreadyCompleted = false
        var subscription: Subscription
        subscription = self.subscribe(
          proc(newVal: T): void =
            subscriber.onNext(newVal)
            counter += 1
            if counter >= num and subscriber.onCompleted.isSome:
              subscriber.onCompleted.get()()
              if isNil subscription:
                # NOTE: Is subscription is nil here, it means that the source
                # observable was a behaviorSubject and already had a value,
                # meaning it fired right away. The subscription isn't available at this point,
                # meaning that we will have to dispose it from the outside, which we enable by
                # settin the following flag.
                alreadyCompleted = true
              else:
                subscription.dispose()

        )
        # NOTE: The observable might have completed even at this point,
        # which means that we need to dispose the subscription already
        if alreadyCompleted:
          subscription.dispose()

        subscription
  )

import options
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

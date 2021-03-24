import options, sugar, tables, hashes, lists
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


type Sublist[A] = ref object
  id: int
  obs: ObservableCollection[A]
  length: int
proc `$`(self: Sublist): string =
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
  ObservableCollection[A](
    onSubscribe: proc(subscriber: CollectionSubscriber[A]): Subscription =

      var positionList = initDoublyLinkedList[Sublist[A]]()
      var values = initTable[Sublist[A], seq[A]]()
      var subscriptions = initTable[Sublist[A], Subscription]()

      proc sublistIndex(self: DoublyLinkedList[Sublist[A]], sublist: Sublist[A]): int =
        for item in self.items():
          if item == sublist:
            break
          result += 1

      proc sublistNode(self: DoublyLinkedList[Sublist[A]], sublist: Sublist[A]): DoublyLinkedNode[Sublist[A]] =
        for node in self.nodes():
          if node.value == sublist:
            return node
        raise newException(Exception, "Couldn't find node in sublist")

      proc sublistNodeAtIndex(self: DoublyLinkedList[Sublist[A]], index: int): Option[DoublyLinkedNode[Sublist[A]]] =
        var i = 0
        for node in self.nodes():
          if i == index:
            return some(node)
          i += 1

      proc sublistAtIndex(self: DoublyLinkedList[Sublist[A]], index: int): Option[Sublist[A]] =
        let x = self.sublistNodeAtIndex(index)
        if x.isSome:
          return some(x.get.value)

      proc offsetForSublist(self: DoublyLinkedList[Sublist[A]], sublist: Sublist[A]): int =
        var index = 0
        var node = self.sublistNode(sublist)
        while not isNil(node.prev):
          node = node.prev
          index += node.value.length
        return index

      proc length(self: DoublyLinkedList[Sublist[A]]): int =
        for item in self.items:
          result += 1

      proc createSubscription(obs: ObservableCollection[A], atIndex: int): void =
        let sublist = initSublist(obs)
        values[sublist] = @[]
        let newNode = newDoublyLinkedNode(sublist)
        if atIndex > 0:
          let nodeBeforeIndex = positionList.sublistNodeAtIndex(atIndex - 1).get

          newNode.prev = nodeBeforeIndex
          newNode.next = nodeBeforeIndex.next
          nodeBeforeIndex.next = newNode

        let listLen = positionList.length

        if atIndex == 0:
          if atIndex < listLen:
            newNode.next = positionList.sublistNodeAtIndex(atIndex).get
          positionList.head = newNode
        elif atIndex == listLen:
          positionList.tail = newNode

        subscriptions[sublist] = sublist.obs.subscribe(
          proc(change: Change[A]): void =
            case change.kind:
              of ChangeKind.Added:
                subscriber.onChanged(Change[A](
                  kind: ChangeKind.Added,
                  newItem: change.newItem,
                  addedAtIndex: positionList.offsetForSublist(sublist) + change.addedAtIndex
                ))
                values[sublist].add(change.newItem)
                sublist.length += 1
              of ChangeKind.Removed:
                subscriber.onChanged(Change[A](
                  kind: ChangeKind.Removed,
                  removedItem: change.removedItem,
                  removedFromIndex: positionList.offsetForSublist(sublist) + change.removedFromIndex
                ))
                values[sublist].delete(values[sublist].find(change.removedItem))
                sublist.length -= 1
              of ChangeKind.Changed:
                subscriber.onChanged(Change[A](
                  kind: ChangeKind.Changed,
                  oldVal: change.oldVal,
                  newVal: change.newVal,
                  changedAtIndex: positionList.offsetForSublist(sublist) + change.changedAtIndex
                ))
                values[sublist][change.changedAtIndex] = change.newVal
              of ChangeKind.InitialItems:
                for (index, item) in change.items.pairs():
                  subscriber.onChanged(Change[A](
                    kind: ChangeKind.Added,
                    addedAtIndex: positionList.offsetForSublist(sublist) + index,
                    newItem: item
                  ))
                  values[sublist].add(item)
                  sublist.length += 1
        )

      let subscription = self.subscribe(
        proc(change: Change[ObservableCollection[A]]): void =
          case change.kind:
            of ChangeKind.Added:
              createSubscription(change.newItem, change.addedAtIndex)
            of ChangeKind.Removed:
              # TODO: Handle removal of collection in switched nested collections
              let node = positionList.sublistNodeAtIndex(change.removedFromIndex).get
              let sublist = node.value
              for (index, value) in values[sublist].pairs():
                subscriber.onChanged(Change[A](
                  kind: ChangeKind.Removed,
                  removedItem: value,
                  removedFromIndex: positionList.offsetForSublist(sublist)
                ))
              values.del(sublist)
              positionList.remove(node)
              subscriptions[sublist].dispose()
              subscriptions.del(sublist)
            of ChangeKind.Changed:
              let sublist = positionList.sublistAtIndex(change.changedAtIndex).get
              subscriptions[sublist].dispose()
              createSubscription(change.newVal, change.changedAtIndex)
            of ChangeKind.InitialItems:
              let items: seq[ObservableCollection[A]] = change.items
              for (index, initialItem) in items.pairs():
                createSubscription(initialItem, index)
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

proc `or`*(self: Observable[bool], other: Observable[bool]): Observable[bool] =
  self.combineLatest(other, (a: bool, b: bool) => a or b)

proc `and`*(self: Observable[bool], other: Observable[bool]): Observable[bool] =
  self.combineLatest(other, (a: bool, b: bool) => a and b)

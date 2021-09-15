import tables, options, sequtils, sugar, strformat, sets
import types
import utils
import observables
import observable_collection

proc observableTable*[TKey, TValue](initialItems: OrderedTableRef[TKey, TValue] = newOrderedTable[TKey, TValue]()): TableSubject[TKey, TValue] =
  let subject = TableSubject[TKey, TValue](
    items: initialItems,
  )
  subject.source = ObservableTable[TKey, TValue](
    onSubscribe: proc(subscriber: TableSubscriber[TKey, TValue]): Subscription =
      subject.subscribers.add(subscriber)
      for k, v in subject.items.pairs:
        subscriber.onSet(k, v)
      Subscription(
        dispose: proc(): void =
          subject.subscribers.delete(subject.subscribers.find(subscriber))
      )
  )
  subject

proc set*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey, value: TValue): void =
  self.items[key] = value
  # NOTE: We assign here to make a copy in case any handler changes the subject subscribers list
  let subscribers = self.subscribers
  for subscriber in subscribers:
    subscriber.onSet(key, value)

proc delete*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): Option[TValue] =
  if self.items.hasKey(key):
    let val = self.items[key]
    result = some[TValue](val)
    self.items.del(key)
    for subscriber in self.subscribers:
      subscriber.onDeleted(key, val)
  else:
    result = none[TValue]()

proc subscribe*[TKey, TValue](self: ObservableTable[TKey, TValue], onSet: (TKey, TValue) -> void, onDeleted: (TKey, TValue) -> void): Subscription =
  self.onSubscribe(
    TableSubscriber[TKey, TValue](
      onSet: onSet,
      onDeleted: onDeleted
    )
  )

template subscribe*[TKey, TValue](self: TableSubject[TKey, TValue], onSet: (TKey, TValue) -> void, onDeleted: (TKey, TValue) -> void): Subscription =
  self.source.subscribe(onSet, onDeleted)

proc getCurrentValue*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): Option[TValue] =
  assert(not isNil(self))
  if key in self.items:
    some(self.items[key])
  else:
    none[TValue]()

proc getFirstKeyForValue*[TKey, TValue](self: TableSubject[TKey, TValue], value: TValue): Option[TKey] =
  for k,v in self.items.pairs:
    if v == value:
      return some(k)
  return none[TKey]()



proc get*[TKey, TValue](self: ObservableTable[TKey, TValue], key: TKey): Observable[Option[TValue]] =
  Observable[Option[TValue]](
    onSubscribe: proc(subscriber: Subscriber[Option[TValue]]): Subscription =
      self.subscribe(
        proc(k: TKey, val: TValue): void =
          if key == k:
            subscriber.onNext(some(val)),
        proc(k: TKey, val: TValue): void =
          if key == k:
            subscriber.onNext(none[TValue]())
      )
  )

template get*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): Observable[Option[TValue]] =
  self.source.get(key)

proc get*[TKey, TValue](self: ObservableTable[TKey,TValue], key: Observable[TKey]): Observable[Option[TValue]] =
  var items = initTable[TKey,TValue]()
  Observable[Option[TValue]](
    onSubscribe: proc(subscriber: Subscriber[Option[TValue]]): Subscription =
      var currentKey: TKey
      let keySub = key.subscribe(
        proc(newKey: TKey): void =
          if newKey != currentKey:
            currentKey = newKey
            if newKey in items:
              subscriber.onNext(some(items[newKey]))
            else:
              subscriber.onNext(none[TValue]())
      )
      let valueSub = self.subscribe(
        proc(k: TKey, val: TValue): void =
          items[k] = val
          if currentKey == k:
            subscriber.onNext(some(val)),
        proc(k: TKey, val: TValue): void =
          items.del(k)
          if currentKey == k:
            subscriber.onNext(none[TValue]())
      )
      Subscription(
        dispose: proc() =
          keySub.dispose()
          valueSub.dispose()
      )
  )

template get*[TKey, TValue](self: TableSubject[TKey,TValue], key: Observable[TKey]): Observable[Option[TValue]] =
  self.source.get(key)

proc `[]=`*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey, value: TValue): void =
  self.set(key, value)

proc `[]`*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): Observable[Option[TValue]] =
  self.get(key)

proc hasKey*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): bool =
  self.items.hasKey(key)

proc contains*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): bool =
  self.hasKey(key)

proc mgetorput*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey, value: TValue): TValue =
  if key notin self:
    self[key] = value
  self.items[key]


proc keys*[TKey, TValue](self: ObservableTable[TKey, TValue]): ObservableCollection[TKey] =
  var keys: seq[TKey] = @[]
  ObservableCollection[TKey](
    onSubscribe: proc(subscriber: CollectionSubscriber[TKey]): Subscription =
      self.subscribe(
        proc(key: TKey, val: TValue): void =
          if key notin keys:
            keys.add(key)
            subscriber.onChanged(Change[TKey](
              kind: ChangeKind.Added,
              newItem: key
            )),
        proc(key: TKey, val: TValue): void =
          # NOTE: It shouldn't be possible to get to a state
          # where keys doesn't contain key at this point, so we're
          # not checking for it.
          keys.delete(keys.find(key))
          subscriber.onChanged(Change[TKey](
            kind: ChangeKind.Removed,
            removedItem: key
          )),
      )
  )

proc values*[TKey, TValue](self: ObservableTable[TKey, TValue]): ObservableCollection[TValue] =
  var keys: seq[TKey] = @[]
  var values = initOrderedTable[TKey,TValue]()
  ObservableCollection[TValue](
    onSubscribe: proc(subscriber: CollectionSubscriber[TValue]): Subscription =
      self.subscribe(
        proc(key: TKey, val: TValue): void =
          if key notin keys:
            let index = keys.len
            keys.add(key)
            values[key] = val
            subscriber.onChanged(Change[TValue](
              kind: ChangeKind.Added,
              newItem: val,
              addedAtIndex: index
            ))
          else:
            let index = keys.find(key)
            let oldVal = values[key]
            values[key] = val
            subscriber.onChanged(
              Change[TValue](
                kind: ChangeKind.Changed,
                changedAtIndex: index,
                oldVal: oldVal,
                newVal: val,
              )
            ),
        proc(key: TKey, val: TValue): void =
          let keyIndex = keys.find(key)
          values.del(key)
          keys.delete(keyIndex)
          subscriber.onChanged(
            Change[TValue](
              kind: ChangeKind.Removed,
              removedItem: val,
              removedFromIndex: keyIndex
            )
          )
      )
  )

proc pairs*[TKey, TValue](self: ObservableTable[TKey, TValue]): ObservableCollection[(TKey, TValue)] =
  var keys: seq[TKey] = @[]
  var values = initOrderedTable[TKey,TValue]()
  ObservableCollection[TValue](
    onSubscribe: proc(subscriber: CollectionSubscriber[TValue]): Subscription =
      self.subscribe(
        proc(key: TKey, val: TValue): void =
          if key notin keys:
            let index = keys.len
            keys.add(key)
            values[key] = val
            subscriber.onChanged(Change[TValue](
              kind: ChangeKind.Added,
              newItem: (key, val),
              addedAtIndex: index
            ))
          else:
            let index = keys.find(key)
            let oldVal = values[key]
            values[key] = val
            subscriber.onChanged(
              Change[TValue](
                kind: ChangeKind.Changed,
                changedAtIndex: index,
                oldVal: (key, oldVal),
                newVal: (key, val),
              )
            ),
        proc(key: TKey, val: TValue): void =
          let keyIndex = keys.find(key)
          values.del(key)
          keys.delete(keyIndex)
          subscriber.onChanged(
            Change[TValue](
              kind: ChangeKind.Removed,
              removedItem: (key, val),
              removedFromIndex: keyIndex
            )
          )
      )
  )

template values*[TKey, TValue](self: TableSubject[TKey, TValue]): ObservableCollection[TValue] =
  self.source.values()

proc toObservableTable*[TKey, TValue](self: Observable[seq[TKey]], mapper: TKey -> TValue): ObservableTable[TKey, TValue] =
  let values = newTable[TKey, TValue]()
  ObservableTable[TKey, TValue](
    onSubscribe: proc(subscriber: TableSubscriber[TKey, TValue]): Subscription =
      self.subscribe(
        proc(newVal: seq[TKey]): void =
          var toDelete: seq[(TKey, TValue)] = @[]
          for k, v in values.pairs:
            if k notin newVal:
              toDelete.add((k, v))
          for i in toDelete:
            let (k, v) = i
            values.del(k)
            subscriber.onDeleted(k, v)
          # TODO: Optimize
          for item in newVal:
            let v = mapper(item)
            if not(values.hasKey(item)) or values[item] != v:
              values[item] =  v
              subscriber.onSet(item, v)
      )
  )

type
  RefCount[T] = ref object
    value: T
    count: int
proc retain(self: RefCount): void =
  self.count += 1
proc release(self: RefCount): void =
  self.count -= 1

proc initRefCount[T](value: T): RefCount[T] =
  RefCount[T](value: value, count: 0)

proc mapToTable*[TKey, TValue](self: ObservableCollection[TKey], mapper: TKey -> TValue): ObservableTable[TKey, TValue] =
  var values = initOrderedTable[TKey, RefCount[TValue]]()
  ObservableTable[TKey, TValue](
    onSubscribe: proc(subscriber: TableSubscriber[TKey, TValue]): Subscription =
      proc retain(key: TKey): void =
        values[key].retain()

      proc release(key: TKey): void =
        values[key].release()

      proc setItem(key: TKey): void =
        if not values.hasKey(key):
          values[key] = initRefCount(mapper(key))
        key.retain()
        subscriber.onSet(key, values[key].value)

      proc deleteItem(key: TKey): void =
        key.release()
        let refCount = values[key]
        if refCount.count == 0:
          values.del(key)
          subscriber.onDeleted(key, refCount.value)


      self.subscribe(
        proc(change: Change[TKey]): void =
          case change.kind:
            of ChangeKind.Added:
              setItem(change.newItem)
            of ChangeKind.Removed:
              deleteItem(change.removedItem)
            of ChangeKind.Changed:
              deleteItem(change.oldVal)
              setItem(change.newVal)
            of ChangeKind.InitialItems:
              for item in change.items:
                setItem(item)
      )
  )

proc mapToTable*[TKey, TValue](self: CollectionSubject[TKey], mapper: TKey -> TValue): ObservableTable[TKey, TValue] =
  self.source.mapToTable(mapper)


proc toObservableTable*[T, TKey, TValue](self: ObservableCollection[T], mapper: T -> (TKey, TValue)): ObservableTable[TKey, TValue] =
  ## NOTE: We require T and TKey to be hashable
  var values = newOrderedTable[TKey, OrderedTableRef[T, TValue]]()
  var keys = newOrderedTable[T, RefCount[TKey]]()

  ObservableTable[TKey, TValue](
    onSubscribe: proc(subscriber: TableSubscriber[TKey, TValue]): Subscription =
      proc setItem(originalKey: T): void =
        if not keys.hasKey(originalKey):
          let (key, value) = mapper(originalKey)
          keys[originalKey] = initRefCount(key)

          if not values.hasKey(key):
            values[key] = newOrderedTable[T, TValue]()
          values[key][originalKey] = value

        let key = keys[originalKey]
        let value = values[key.value]

        key.retain()
        subscriber.onSet(key.value, value[originalKey])

      proc deleteItem(originalKey: T): void =
        let key = keys[originalKey]

        key.release()


        if key.count == 0:
          keys.del(originalKey)

        let value = values[key.value]
        if value.len > 0:
          let actualValue = value[originalKey]
          value.del(originalKey)
          if value.len == 0:
            subscriber.onDeleted(key.value, actualValue)
          else:
            let pairs = toSeq(value.values())
            let newValue = pairs[pairs.len - 1]
            subscriber.onSet(key.value, newValue)

      self.subscribe(
        proc(change: Change[T]): void =
          case change.kind:
            of ChangeKind.Added:
              setItem(change.newItem)
            of ChangeKind.Removed:
              deleteItem(change.removedItem)
            of ChangeKind.Changed:
              deleteItem(change.oldVal)
              setItem(change.newVal)
            of ChangeKind.InitialItems:
              for item in change.items:
                setItem(item)
      )
  )

proc toObservableTable*[T, TKey, TValue](self: CollectionSubject[T], mapper: T-> (TKey,TValue)): ObservableTable[TKey, TValue] =
  self.source.toObservableTable(mapper)


# NOTE: HACK
proc cache*[TKey, TValue](self: ObservableTable[TKey, TValue]): TableSubject[TKey, TValue] =
  let subject = observableTable[TKey, TValue]()
  discard self.subscribe(
    proc(key: TKey, val: TValue): void =
      subject.items[key] = val
      for subscriber in subject.subscribers:
        subscriber.onSet(key, val),
    proc(key: TKey, val: TValue): void =
      subject.items.del(key)
      for subscriber in subject.subscribers:
        subscriber.onDeleted(key, val)
  )
  subject


proc map*[K,V,KR,VR](self: ObservableTable[K,V], mapper: (K,V) -> (KR,VR)): ObservableTable[KR,VR] =
  # NOTE: Maintaining a cache here so that we don't have to call
  # the mapper when we are emitting onDeleted events.
  var values = initTable[K, (KR, VR)]()
  ObservableTable[KR, VR](
    onSubscribe: proc(subscriber: TableSubscriber[KR, VR]): Subscription =
      self.subscribe(
        proc(key: K, val: V): void =
          let (keyRes, valRes) = mapper(key, val)
          values[key] = (keyRes, valRes)
          subscriber.onSet(keyRes, valRes),
        proc(key: K, val: V): void =
          let (keyRes, valRes) = values[key]
          values.del(key)
          subscriber.onDeleted(keyRes, valRes)
      )
  )

template map*[K,V,KR,VR](self: TableSubject[K,V], mapper: (K,V) -> (KR,VR)): ObservableTable[KR,VR] =
  self.source.map(mapper)

proc filter*[K,V](self: ObservableTable[K,V], predicate: (K,V) -> bool): ObservableTable[K,V] =
  ObservableTable[K, V](
    onSubscribe: proc(subscriber: TableSubscriber[K, V]): Subscription =
      self.subscribe(
        proc(key: K, val: V): void =
          if predicate(key, val):
            subscriber.onSet(key, val),
        proc(key: K, val: V): void =
          if predicate(key, val):
            subscriber.onDeleted(key, val)
      )
  )

template filter*[K,V](self: TableSubject[K,V], predicate: (K,V) -> bool): ObservableTable[K,V] =
  self.source.filter(predicate)

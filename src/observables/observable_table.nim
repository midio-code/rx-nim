import tables, options, sequtils, sugar, strformat
import types
import utils
import observables
import observable_collection

proc observableTable*[TKey, TValue](initialItems: TableRef[TKey, TValue] = newTable[TKey, TValue]()): TableSubject[TKey, TValue] =
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
  for subscriber in self.subscribers:
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

proc keys*[TKey, TValue](self: ObservableTable[TKey, TValue]): ObservableCollection[TKey] =
  var keys: seq[TKey] = @[]
  ObservableCollection[TKey](
    onSubscribe: proc(subscriber: CollectionSubscriber[TKey]): Subscription =
      self.subscribe(
        proc(key: TKey, val: TValue): void =
          if key notin keys:
            keys.add(key)
            subscriber.onAdded(key),
        proc(key: TKey, val: TValue): void =
          # NOTE: It shouldn't be possible to get to a state
          # where keys doesn't contain key at this point, so we're
          # not checking for it.
          keys.delete(keys.find(key))
          subscriber.onRemoved(key)
      )
  )

proc values*[TKey, TValue](self: ObservableTable[TKey, TValue]): ObservableCollection[TValue] =
  var values: seq[TValue] = @[]
  ObservableCollection[TValue](
    onSubscribe: proc(subscriber: CollectionSubscriber[TValue]): Subscription =
      self.subscribe(
        proc(key: TKey, val: TValue): void =
          if val notin values:
            values.add(val)
            subscriber.onAdded(val),
        proc(key: TKey, val: TValue): void =
          # NOTE: It shouldn't be possible to get to a state
          # where keys doesn't contain key at this point, so we're
          # not checking for it.
          values.delete(values.find(val))
          subscriber.onRemoved(val)
      )
  )

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

proc toObservableTable*[TKey, TValue](self: ObservableCollection[TKey], mapper: TKey -> TValue): ObservableTable[TKey, TValue] =
  let values = newTable[TKey, TValue]()
  ObservableTable[TKey, TValue](
    onSubscribe: proc(subscriber: TableSubscriber[TKey, TValue]): Subscription =
      self.subscribe(
        proc(item: TKey): void =
          if not(values.hasKey(item)):
            let v = mapper(item)
            values[item] =  v
            subscriber.onSet(item, v),
        proc(removed: TKey): void =
          let ret = values[removed]
          values.del(removed)
          subscriber.onDeleted(removed, ret),
        proc(initialItems: seq[TKey]): void =
          var toDelete: seq[(TKey, TValue)] = @[]
          for k, v in values.pairs:
            if k notin initialItems:
              toDelete.add((k, v))
          for i in toDelete:
            let (k, v) = i
            values.del(k)
            subscriber.onDeleted(k, v)
          # TODO: Optimize
          for item in initialItems:
            let v = mapper(item)
            if not(values.hasKey(item)) or values[item] != v:
              values[item] =  v
              subscriber.onSet(item, v)
      )
  )

proc toObservableTable*[TKey, TValue](self: CollectionSubject[TKey], mapper: TKey -> TValue): ObservableTable[TKey, TValue] =
  self.source.toObservableTable(mapper)


# TODO: Find a better name to disambiguate with the other toObservableTable proc
proc toObservableTableKV*[T, TKey, TValue](self: ObservableCollection[T], mapper: T-> (TKey, TValue)): ObservableTable[TKey, TValue] =
  let values = newTable[TKey, TValue]()
  ObservableTable[TKey, TValue](
    onSubscribe: proc(subscriber: TableSubscriber[TKey, TValue]): Subscription =
      self.subscribe(
        proc(item: T): void =
          if not(values.hasKey(item)):
            let (k, v) = mapper(item)
            values[k] =  v
            subscriber.onSet(k, v),
        proc(removed: T): void =
          let ret = values[removed]
          let (k, v) = mapper(removed)
          values.del(k)
          subscriber.onDeleted(k, ret),
        proc(initialItems: seq[T]): void =
          var toDelete: seq[(TKey, TValue)] = @[]
          for k, v in values.pairs:
            if k notin initialItems:
              toDelete.add((k, v))
          for i in toDelete:
            let (k, v) = i
            values.del(k)
            subscriber.onDeleted(k, v)
          # TODO: Optimize
          for item in initialItems:
            let (k, v) = mapper(item)
            if not(values.hasKey(k)) or values[k] != v:
              values[k] =  v
              subscriber.onSet(k, v)
      )
  )

proc toObservableTableKV*[T, TKey, TValue](self: CollectionSubject[T], mapper: T-> (TKey, TValue)): ObservableTable[TKey, TValue] =
  toObservableTableKV(self, mapper)

# NOTE: HACK
proc cache*[TKey, TValue](self: ObservableTable[TKey, TValue]): ObservableTable[TKey, TValue] =
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
  subject.source

template cache*[TKey, TValue](self: TableSubject[TKey, TValue]): ObservableTable[TKey, TValue] =
  self.source.cache()


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

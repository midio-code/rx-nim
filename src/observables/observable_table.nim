import tables, options, sequtils, sugar
import types
import utils
import observables

proc observableTable*[TKey, TValue](initialItems: TableRef[TKey, TValue] = newTable[TKey, TValue]()): TableSubject[TKey, TValue] =
  let subject = TableSubject[TKey, TValue](
    values: initialItems,
  )
  subject.source = ObservableTable[TKey, TValue](
    onSubscribe: proc(subscriber: TableSubscriber[TKey, TValue]): Subscription =
      subject.subscribers.add(subscriber)
      for k, v in subject.values.pairs:
        subscriber.onSet(k, v)
      Subscription(
        dispose: proc(): void =
          subject.subscribers.remove(subscriber)
      )
  )
  subject

proc set*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey, value: TValue): void =
  self.values[key] = value
  for subscriber in self.subscribers:
    subscriber.onSet(key, value)

proc delete*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): Option[TValue] =
  if self.values.hasKey(key):
    let val = self.values[key]
    result = some[TValue](val)
    self.values.del(key)
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

converter toObservableTable*[TKey, TValue](self: TableSubject[TKey, TValue]): ObservableTable[TKey, TValue] =
  self.source

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

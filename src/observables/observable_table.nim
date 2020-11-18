import tables, options, sequtils, sugar
import types
import utils

proc observableTable*[TKey, TValue](initialItems: TableRef[TKey, TValue]): TableSubject[TKey, TValue] =
  let subject = TableSubject[TKey, TValue](
    values: initialItems,
  )
  subject.source = ObservableTable[TKey, TValue](
    onSubscribe: proc(subscriber: TableSubscriber[TKey, TValue]): Subscription =
      subject.subscribers.add(subscriber)
      for k, v in subject.values.pairs:
        subscriber.onPut(k, v)
      Subscription(
        dispose: proc(): void =
          subject.subscribers.remove(subscriber)
      )
  )
  subject

proc put*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey, value: TValue): void =
  self.values[key] = value
  for subscriber in self.subscribers:
    subscriber.onPut(key, value)

proc delete*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): Option[TValue] =
  if self.values.hasKey(key):
    let val = self.values[key]
    result = some[TValue](val)
    self.values.del(key)
    for subscriber in self.subscribers:
      subscriber.onDeleted(key, val)
  else:
    result = none[TValue]()

proc subscribe*[TKey, TValue](self: ObservableTable[TKey, TValue], onPut: (TKey, TValue) -> void, onDeleted: (TKey, TValue) -> void): Subscription =
  self.onSubscribe(
    TableSubscriber[TKey, TValue](
      onPut: onPut,
      onDeleted: onDeleted
    )
  )

converter toObservableTable*[TKey, TValue](self: TableSubject[TKey, TValue]): ObservableTable[TKey, TValue] =
  self.source

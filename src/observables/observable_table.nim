import tables, options, sequtils
import types
import utils

proc observableTable*[TKey, TValue](initialItems: Table[TKey, TValue]): TableSubject[TKey, TValue] =
  let subject = TableSubject(
    values: initialItems,
  )
  subject.source = ObservableTable[TKey, TValue](
    onSubscribe: proc(subscriber: TableSubscriber[TKey, TValue]): Subscription =
      subject.subscribers.add(subscriber)
      for k, v in subject.values.items:
        subscriber.onPut(k, v)
      Subscription(
        dispose: proc(): void =
          subject.subscribers.remove(subscriber)
      )
  )

proc put*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey, value: TValue): void =
  self.values.put(key, value)
  for subscriber in self.subscribers:
    subscriber.onPut(key, value)

proc delete*[TKey, TValue](self: TableSubject[TKey, TValue], key: TKey): Option[TValue] =
  var val: TValue
  if self.values.del(key, val):
    for subscriber in self.subscribers:
      subscriber.onDeleted(key, val)
    some(val)
  else:
    none[TValue]()

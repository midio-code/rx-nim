import sugar
import sequtils
import lists
import options
import tables
import unittest
import src/rx_nim
import hashes

proc hash(self: Option[string]): Hash =
  if self.isSome:
    self.get.hash()
  else:
    0

suite "observable tests":
  test "Observable test 1":
    let subj = behaviorSubject(123)
    var test = 0
    discard subj.subscribe((val: int) => (test = val))
    check(test == 123)
    subj.next(321)
    check(test == 321)
    discard subj.subscribe((val: int) => (test = 555))
    check(test == 555)

  test "Map operator":
    let subj = behaviorSubject[int](2)
    let mapped = subj.source.map(
      proc(x: int): int =
        x * x
    )
    var val = 0
    discard mapped.subscribe(
      proc(newVal: int): void =
        val = newVal
    )
    check(val == 4)
    subj.next(9)
    check(val == 81)

  test "Two maps":
    let subj = behaviorSubject[int](2)
    let first = subj.source.map(
      proc(x: int): int =
        x * x
    )
    let second = first.map(
      proc(x: int): int =
        x * 10
    )
    var res = 0
    discard second.subscribe(
      proc(y: int): void =
        res = y
    )
    check(res == 40)

  test "Combine latest":
    let s1 = behaviorSubject(5)
    let s2 = behaviorSubject(10)
    let combined = s1.source.combineLatest(s2.source, (a,b) => (a + b))
    var res = 0
    discard combined.subscribe((newVal: int) => (res = newVal))
    check(res == 15)

  test "Subject wrapping observable":
    let subj1 = behaviorSubject(10)
    let m1 = subj1.map((x: int) => x * x)
    let subj2 = behaviorSubject(m1)
    check(subj2.value == 100)
    subj1.next(5)
    check(subj2.value == 25)

  test "Subscription test":
    let s = behaviorSubject(10)
    var subscriptionCalls = 0
    discard s.source.subscribe(
      proc(x: int): void =
        subscriptionCalls += 1
    )
    check(subscriptionCalls == 1)
    discard s.source.subscribe(
      proc(x: int): void =
        subscriptionCalls += 1
    )
    check(subscriptionCalls == 2)
    s.next(123)
    check(subscriptionCalls == 4)

  test "Completing observable":
    let obs = createObservable(@[1,2,3,4,5])
    var value = 0
    var completed = false
    discard obs.subscribe(
      proc(val: int) = value += val,
      proc() = completed = true
    )

    check(value == 1+2+3+4+5)
    check(completed == true)

  test "Completing subject":
    let subj = behaviorSubject(1)
    subj.next(2)
    check(subj.value == 2)
    subj.complete()

    expect(Exception):
      subj.next(3)

  test "Observable then":
    let a = createObservable(@[1,3,5])
    let b = createObservable(@[2,4,6])

    let combined = a.then(b)

    var sum = 0
    var completed = 0
    discard combined.subscribe(
      proc(val: int) =
        sum += val
        check(completed == 0)
      ,
      proc() = completed += 1
    )
    check(sum == 1+2+3+4+5+6)
    check(completed == 1)

  test "Observable.take":
    let subj = behaviorSubject(1)
    let one = subj.source.take(1)
    var oneComplete = 0
    var oneSum = 0
    discard one.subscribe(
      proc(val: int): void =
        oneSum += val,
      proc(): void =
        oneComplete += 1
    )

    check(oneSum == 1)
    check(oneComplete == 1)
    subj.next(4)
    check(oneSum == 1)
    check(oneComplete == 1)

    let two = subj.source.take(2)
    var twoComplete = 0
    var twoSum = 0
    discard two.subscribe(
      proc(val: int): void =
        twoSum += val,
      proc(): void =
        twoComplete += 1
    )
    check(twoSum == 4)
    check(oneComplete == 1)
    check(twoComplete == 0)

    subj.next(10)
    check(twoSum == 14)
    check(oneComplete == 1)
    check(twoComplete == 1)

    subj.next(20)
    check(twoSum == 14)
    check(oneComplete == 1)
    check(twoComplete == 1)

  test "Observable.unique":
    let s = behaviorSubject(1)
    let v = s.unique.behaviorSubject
    var count = 0
    discard v.subscribe(
      proc(val: int): void =
        count += 1
    )

    check(count == 1)
    s <- 1
    s <- 1
    check(count == 1)
    s <- 2
    check(count == 2)
    s <- 2
    check(count == 2)
    s <- 3
    check(count == 3)


suite "observable collection tests":
  test "Added and removed notifications":
    let collection: CollectionSubject[int] = observableCollection[int]()
    var total = 0
    discard collection.subscribe(
      proc(item: int): void =
        total += item
      ,
      proc(item: int): void =
        total -= item
    )
    check(total == 0)
    collection.add(10)
    check(total == 10)
    collection.add(5)
    check(total == 15)
    collection.remove(10)
    check(total == 5)

  test "Mapping observable collection":
    let start: seq[int] = @[]
    let collection: CollectionSubject[int] = observableCollection(start)
    var total = 0
    discard collection.subscribe(
      proc(item: int): void =
        total += item
      ,
      proc(item: int): void =
        total -= item
    )
    var mapped = 0
    let mappedCollection = collection.map(
      proc(x: int): int =
        x * 2
    )
    discard mappedCollection.subscribe(
      proc(item: int): void =
        mapped += item
      ,
      proc(item: int): void =
        mapped -= item
    )

    check(total == 0)
    check(mapped == 0)
    collection.add(10)
    check(total == 10)
    check(mapped == 20)
    collection.add(5)
    check(total == 15)
    check(mapped == 30)
    collection.remove(10)
    check(total == 5)
    check(mapped == 10)

  test "Another mapping observable collection":
    let collection = observableCollection[int](@[])
    var total = 0
    var a = 0
    var b = 0
    let mappedCollection = collection.map(
      proc(x: int): int =
        total += 1
        x
    )
    discard mappedCollection.subscribe(
      proc(item: int): void =
        a += 1
      ,
      proc(item: int): void =
        a -= 1
    )
    discard mappedCollection.subscribe(
      proc(item: int): void =
        b += 1
      ,
      proc(item: int): void =
        b -= 1
    )
    collection.add(1)
    collection.add(2)
    collection.add(3)
    collection.add(4)

    check(total == 8) # This is 8 because the subscriptions are
                      # kept by collection (which is the subject),
                      # meaning that for each of the mappings, the mappedCollection mapping
                      # will be called (one time per second mapping)
    check(a == 4)
    check(b == 4)

  test "ObservableCollection.contains":
    let collection = observableCollection[int](@[])
    let c = collection.contains(10)
    let val = behaviorSubject(c)

    check(val.value == false)
    collection.add(10)
    check(val.value == true)
    collection.add(11)
    check(val.value == true)
    collection.remove(11)
    check(val.value == true)
    collection.remove(10)
    check(val.value == false)

  test "ObservableCollection.contains - already items in the collection":
    let collection = observableCollection[int](@[10])
    let c = collection.contains(10)
    let val = behaviorSubject(c)

    check(val.value == true)
    collection.add(10)
    check(val.value == true)
    collection.add(11)
    check(val.value == true)
    collection.remove(11)
    check(val.value == true)
    collection.remove(10)
    check(val.value == true)
    collection.remove(10)
    check(val.value == false)

  test "ObservableCollection.len":
    let collection = observableCollection[int](@[])
    let c = collection.len()
    let val = behaviorSubject(c)

    check(val.value == 0)
    collection.add(1)
    check(val.value == 1)
    collection.add(1)
    check(val.value == 2)
    collection.add(2)
    collection.add(2)
    check(val.value == 4)
    collection.remove(2)
    check(val.value == 3)

  test "ObservableCollection.filter":
    let collection = observableCollection[string]()

    let f = collection.source.filter(
      proc(s: string): bool =
        s.len > 3
    )

    let vals = f.cache
    check(vals.values.len == 0)

    collection.add("foo")
    check(vals.values.len == 0)

    collection.add("first")
    check(vals.values.len == 1)
    check(vals.values[0] == "first")

    collection.add("second")
    collection.add("bar")
    collection.add("last")

    check(vals.values.len == 3)
    check(vals.values[0] == "first")
    check(vals.values[1] == "second")
    check(vals.values[2] == "last")

    collection.remove("second")
    check(vals.values.len == 2)
    check(vals.values[0] == "first")
    check(vals.values[1] == "last")

    collection.insert("testing", 0)
    check(vals.values.len == 3)
    check(vals.values[0] == "testing")
    check(vals.values[1] == "first")
    check(vals.values[2] == "last")

    collection.insert("baz", 0)
    check(vals.values.len == 3)
    check(vals.values[0] == "testing")
    check(vals.values[1] == "first")
    check(vals.values[2] == "last")

    collection.set(3, "setting")
    check(vals.values.len == 3)
    check(vals.values[0] == "testing")
    check(vals.values[1] == "setting")
    check(vals.values[2] == "last")


    collection.set(0, "foobar")
    check(vals.values.len == 4)
    check(vals.values[0] == "foobar")
    check(vals.values[1] == "testing")
    check(vals.values[2] == "setting")
    check(vals.values[3] == "last")


  test "ObservableCollection.switch(Collection[Collection[T]] -> Collection[T])":
    let collection = observableCollection[ObservableCollection[string]]()

    let c = collection.source.switch().cache

    let col1 = observableCollection[string]()
    collection.add(col1.source)

    col1.add("foo")

    check(c.values.len == 1)
    check(c.values[0] == "foo")

    col1.add("bar")
    check(c.values.len == 2)
    check(c.values[0] == "foo")
    check(c.values[1] == "bar")

    let col2 = observableCollection[string]()
    collection.add(col2.source)
    check(c.values.len == 2)
    check(c.values[0] == "foo")
    check(c.values[1] == "bar")

    col2.add("baz")
    check(c.values.len == 3)
    check(c.values[0] == "foo")
    check(c.values[1] == "bar")
    check(c.values[2] == "baz")

    col1.add("biz")
    check(c.values.len == 4)
    check(c.values[0] == "foo")
    check(c.values[1] == "bar")
    check(c.values[2] == "biz")
    check(c.values[3] == "baz")

    col1.remove("bar")
    check(c.values.len == 3)
    check(c.values[0] == "foo")
    check(c.values[1] == "biz")
    check(c.values[2] == "baz")

    col1.insert("first", 0)
    check(c.values.len == 4)
    check(c.values[0] == "first")
    check(c.values[1] == "foo")
    check(c.values[2] == "biz")
    check(c.values[3] == "baz")

    col2.insert("firstInSecond", 0)
    check(c.values.len == 5)
    check(c.values[0] == "first")
    check(c.values[1] == "foo")
    check(c.values[2] == "biz")
    check(c.values[3] == "firstInSecond")
    check(c.values[4] == "baz")

    let behaviorSubj = c.toObservable.map(
      proc(x: seq[string]): seq[string] =
        for y in x:
          result.add(y & "-foo")
    ).behaviorSubject

    collection.remove(col1.source)
    check(c.values.len == 2)
    check(c.values[0] == "firstInSecond")
    check(c.values[1] == "baz")

    check(behaviorSubj.value.len == 2)
    check(behaviorSubj.value[0] == "firstInSecond-foo")
    check(behaviorSubj.value[1] == "baz-foo")

  test "switch and filter ":
    let collection = observableCollection[ObservableCollection[string]]()

    let c = collection.source.switch().filter(
      proc(x: string): bool =
        x.len > 3
    ).cache

    let col1 = observableCollection[string]()
    collection.add(col1.source)

    col1.add("foo")

    check(c.values.len == 0)

    col1.add("bars")
    check(c.values.len == 1)

    let col2 = observableCollection[string]()
    collection.add(col2.source)
    check(c.values.len == 1)

    col2.add("bark")
    check(c.values.len == 2)

    col1.add("bi")
    check(c.values.len == 2)

    echo "Removing bars"
    col1.remove("bars")
    check(c.values.len == 1)

    col1.insert("first", 1)
    check(c.values.len == 2)

    col2.insert("firstInSecond", 0)
    check(c.values.len == 3)

    echo "Removing foo, bi, first"
    collection.remove(col1.source)
    check(c.values.len == 2)

  test "switch and filter 2":
    let collection = observableCollection[ObservableCollection[string]]()

    let c = collection.source.switch().filter(
      proc(x: string): bool =
        x.len > 3
    ).cache

    let col1 = observableCollection[string]()
    collection.add(col1.source)

    col1.add("foo")

    check(c.values.len == 0)
    # []

    col1.add("bars")
    check(c.values.len == 1)
    # [bars]

    let col2 = observableCollection[string]()
    collection.add(col2.source)
    check(c.values.len == 1)
    # [bars]

    col2.add("bark")
    check(c.values.len == 2)
    # [bars, bark]

    col1.add("bi")
    check(c.values.len == 2)
    # [bars, bark]

    echo "Removing bars"
    col1.remove("bars")
    check(c.values.len == 1)
    # [bark]

    col1.insert("first", 1)
    check(c.values.len == 2)
    # [bark, first]

    col2.insert("firstInSecond", 0)
    check(c.values.len == 3)
    # [firstInSecond, bark, first]

    echo "Removing ", col2.values
    collection.remove(col2.source)
    check(c.values.len == 1)
    # [first]

    let col3 = observableCollection[string](@["heisann"])
    collection.add(col3.source)
    check(c.values.len == 2)

  test "switch and filter 3":
    let collection = observableCollection[ObservableCollection[string]]()

    let c = collection.source.switch().filter(
      proc(x: string): bool =
        x.len > 3
    ).cache

    let col1 = observableCollection[string]()
    collection.add(col1.source)

    col1.add("foo")
    col1.add("bars")

    let col2 = observableCollection[string]()
    collection.add(col2.source)
    col2.add("bark")
    col1.add("bi")


    let col3 = observableCollection[string](@["heisann"])
    collection.add(col3.source)

    collection.remove(col2.source)

    let col4 = observableCollection[string](@["dera"])
    collection.add(col4.source)

suite "More observable tests":
  test "Subject (PublishSubject) basics":
    let subj = subject[int]()
    var ret = 123
    subj.next(111)
    check(ret == 123)
    discard subj.source.subscribe(
      proc(val: int): void =
        ret = val
    )
    check(ret == 123)
    subj.next(321)
    check(ret == 321)

  test "Merge":
    let outer = subject[Observable[int]]()

    let merged = outer.source.merge()

    var total = 0
    discard merged.subscribe(
      proc(val: int): void =
        total += val
    )

    let value = behaviorSubject(merged)
    check(value.value == 0)
    check(total == 0)

    let s1 = behaviorSubject(10)
    outer.next(
      s1.source
    )

    check(value.value == 10)
    check(total == 10)

    s1.next(5)
    check(value.value == 5)
    check(total == 15)


    let s2 = behaviorSubject(4)
    outer.next(
      s2.source
    )
    check(value.value == 4)
    check(total == 19)

    s1.next(1)
    check(value.value == 1)
    check(total == 20)

  test "Switch":
    let outer = subject[Observable[int]]()

    let switched = outer.source.switch()

    var total = 0
    discard switched.subscribe(
      proc(val: int): void =
        total += val
    )

    let value = behaviorSubject(switched)
    check(value.value == 0)
    check(total == 0)

    let s1 = behaviorSubject(10)
    outer.next(
      s1.source
    )

    check(value.value == 10)
    check(total == 10)

    s1.next(5)
    check(value.value == 5)
    check(total == 15)


    let s2 = behaviorSubject(4)
    outer.next(
      s2.source
    )
    check(value.value == 4)
    check(total == 19)

    s1.next(1)
    check(value.value == 4)
    check(total == 19)

  test "Collection.switch(Observable) and filter":
    let outer = observableCollection[Observable[int]]()

    let filtered = outer.source.switch().filter(
      proc(x: int): bool =
        x > 3
    ).cache

    let value = behaviorSubject(filtered)

    let s1 = behaviorSubject(10)
    outer.add(s1.source)
    s1 <- 5

    let s2 = behaviorSubject(4)
    outer.add(s2.source)

    outer.remove(s1.source)

    let s3 = behaviorSubject(29)
    outer.add(s3.source)

    check(filtered.values.len == 2)
    check(filtered.values[0] == 4)
    check(filtered.values[1] == 29)
    s3 <- 50
    check(filtered.values[1] == 50)

    outer.remove(s2.source)
    check(filtered.values.len == 1)
    check(filtered.values[0] == 50)

  test "Filter'n switch'n get'n stuff":
    let table = observableTable[int, string]()
    let collection = observableCollection[int]()

    let mapped = collection.map(
      proc(obs: int): Observable[Option[string]] =
        table.get(obs)
    ).switch.filter(
      proc(x: Option[string]): bool =
        x.isSome
    ).map(
      proc(x: Option[string]): string =
        x.get
    ).cache

    collection.add(1)
    check(mapped.values.len == 0)
    table.set(1, "foobar")
    check(mapped.values.len == 1)
    check(mapped.values[0] == "foobar")

    table.set(2, "baz")
    discard table.delete(1)
    check(mapped.values.len == 0)


suite "Observable table":
  test "Basic table test":
    let t = observableTable({"foo": 123, "bar": 321 }.newOrderedTable())
    var c = false
    var r = false
    discard t.source.subscribe(
      proc(key: string, val: int): void =
        if key == "test" and val == 555:
          c = true,
      proc(key: string, val: int): void =
        if key == "foo" and val == 123:
          r = true
    )

    check(c == false)
    t.set("test", 555)
    check(c == true)
    check(r == false)
    let deleted = t.delete("foo")
    check(r == true)

  test "Observable[seq[T]] to TableSubject[T, Key]":
    let original = behaviorSubject(@["foo", "hello"])
    let t = original.source.toObservableTable(
      proc(key: string): int =
        key.len
    )
    var added: seq[(string, int)] = @[]
    var deleted: seq[(string, int)] = @[]
    discard t.subscribe(
      proc(key: string, val: int): void =
        added.add((key, val)),
      proc(key: string, val: int): void =
        deleted.add((key, val))
    )

    check(added.len == 2)
    check(added[0][0] == "foo")
    check(added[0][1] == 3)
    check(added[1][0] == "hello")
    check(added[1][1] == 5)

    original.next(@["foo", "fourth", "a"])
    check(added.len == 4)
    check(added[0][0] == "foo")
    check(added[0][1] == 3)
    check(added[1][0] == "hello")
    check(added[1][1] == 5)
    check(added[2][0] == "fourth")
    check(added[2][1] == 6)
    check(added[3][0] == "a")
    check(added[3][1] == 1)

    check(deleted[0][0] == "hello")
    check(deleted[0][1] == 5)

  test "ObservableTable.get":
    let t = observableTable({"foo": 123, "bar": 321 }.newOrderedTable())
    let val = behaviorSubject(t.get("foo"))

    check(val.value.isSome())
    check(val.value.get() == 123)

    discard t.delete("foo")
    check(val.value.isNone)

    t.set("foo", 222)
    check(val.value.isSome)
    check(val.value.get == 222)

  test "ObservableTable.filter":
    let t = observableTable({ "one": 1, "two": 2, "three": 3, "four": 4, "five": 5 }.newOrderedTable())
    let filtered = t.filter(
      proc(key: string, val: int): bool =
        val < 3
    )

    check(behaviorSubject(filtered.get("one")).value.isSome())
    check(behaviorSubject(filtered.get("two")).value.isSome())
    check(behaviorSubject(filtered.get("three")).value.isNone())
    check(behaviorSubject(filtered.get("four")).value.isNone())
    check(behaviorSubject(filtered.get("five")).value.isNone())

  test "ObservableTable.mapToTable":
    let c = observableCollection(@[1,2,3])
    let t = c.mapToTable(
      proc(k: int): float =
        float(k) + 0.5
    )

    var values = initTable[int, float]()
    discard t.subscribe(
      proc(k: int, v: float): void =
        values[k] = v,
      proc(k: int, v: float): void =
        values.del(k)
    )

    check(values[1] == 1.5)
    check(values[2] == 2.5)
    check(values[3] == 3.5)

    c.add(5)
    check(values[5] == 5.5)
    c.remove(3)
    check(not (3 in values))

  test "ObservableTable.mapToTable with caching":
    let c = observableCollection(@[1,2,3])
    let t = c.mapToTable(
      proc(k: int): float =
        float(k) + 0.5
    ).cache.source

    var values = initTable[int, float]()
    discard t.subscribe(
      proc(k: int, v: float): void =
        values[k] = v,
      proc(k: int, v: float): void =
        values.del(k)
    )

    check(values[1] == 1.5)
    check(values[2] == 2.5)
    check(values[3] == 3.5)

    c.add(5)
    check(values[5] == 5.5)
    c.remove(3)
    check(not (3 in values))

  test "ObservableTable.mapToTable with caching and get":
    let c = observableCollection(@[1,2])
    let t = c.mapToTable(
      proc(k: int): float =
        float(k) + 0.5
    ).cache.source.get(3)

    var value: Option[float] = none[float]()
    discard t.subscribe(
      proc(val: Option[float]): void =
        value = val
    )

    check(value.isNone)
    c.add(3)
    check(value.isSome and value.get == 3.5)

  test "ObservableTable[K,V].get(Observable[K])":
    let t = observableTable[string, int]()
    let key = behaviorSubject("one")

    let x = behaviorSubject(t.get(key.source))

    check(x.value == none[int]())

    t.set("one", 1)
    check(x.value == some(1))

    t.set("two", 2)
    check(x.value == some(1))

    key <- "three"
    check(x.value == none[int]())

    key <- "two"
    check(x.value == some(2))

    discard t.delete("two")
    check(x.value == none[int]())

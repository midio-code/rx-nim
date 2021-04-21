proc remove*[T](self: var seq[T], item: T): void =
  let index = self.find(item)
  if index >= 0:
    self.delete(index)

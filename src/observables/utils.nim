proc remove*[T](self: var seq[T], item: T): void =
  self.delete(self.find(item))

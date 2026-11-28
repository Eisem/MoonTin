///|
priv suberror InputError {
  InputTooLarge(Int32)
  InputChanged
  InvalidUtf8
}

///|
async fn read_input(path : String, limit : Int32) -> String {
  let file = @fs.open(path[:], mode=ReadOnly)
  defer file.close()
  let size = file.size()
  if size > limit.to_int64() {
    raise InputTooLarge(limit)
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0L)
  let probe = FixedArray::make(1, b'\x00')
  if file.read_at(probe, position=size) != 0 {
    if size == limit.to_int64() {
      raise InputTooLarge(limit)
    }
    raise InputChanged
  }
  @utf8.decode(bytes[:]) catch {
    _ => raise InvalidUtf8
  }
}

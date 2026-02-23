///|
fn finalize_offset_off_base(
  raw_offset : Int,
  ll0 : Bool,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> Int raise ZstdError {
  if raw_offset <= 0 {
    raise CorruptionDetected
  }
  if !ll0 && raw_offset == rep1 {
    return 1
  }
  if raw_offset == rep2 {
    return if ll0 { 1 } else { 2 }
  }
  if raw_offset == rep3 {
    return if ll0 { 2 } else { 3 }
  }
  if ll0 && rep1 > 1 && raw_offset == rep1 - 1 {
    return 3
  }
  raw_offset + 3
}

///|
fn update_repcodes_with_off_base(
  ll0 : Bool,
  off_base : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Int, Int, Int) raise ZstdError {
  if off_base <= 0 {
    raise CorruptionDetected
  }
  if off_base > 3 {
    let raw = off_base - 3
    if raw <= 0 {
      raise CorruptionDetected
    }
    return (raw, rep1, rep2)
  }
  let rep_code = off_base - 1 + (if ll0 { 1 } else { 0 })
  if rep_code == 0 {
    return (rep1, rep2, rep3)
  }
  let current = if rep_code == 3 {
    rep1 - 1
  } else if rep_code == 2 {
    rep3
  } else {
    rep2
  }
  if current <= 0 {
    raise CorruptionDetected
  }
  let nr3 = if rep_code >= 2 { rep2 } else { rep3 }
  (current, rep1, nr3)
}

///|
fn offset_symbol_from_off_base(
  off_base : Int,
) -> (UInt, UInt, Int) raise ZstdError {
  if off_base <= 0 {
    raise CorruptionDetected
  }
  let mut bits = 0
  let mut v = off_base
  while v > 1 {
    v = v >> 1
    bits = bits + 1
  }
  if bits > 31 {
    raise CorruptionDetected
  }
  if bits == 0 {
    return (0, (0 : UInt), 0)
  }
  if bits == 1 {
    return (1, (off_base & 1).reinterpret_as_uint(), 1)
  }
  let base = 1 << bits
  let extra = off_base - base
  if extra < 0 {
    raise CorruptionDetected
  }
  let span = (((1 : UInt64) << bits) - (1 : UInt64)).to_int()
  if extra > span {
    raise CorruptionDetected
  }
  (bits.reinterpret_as_uint(), extra.reinterpret_as_uint(), bits)
}

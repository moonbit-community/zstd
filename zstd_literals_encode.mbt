///|
fn append_literals_header(
  out : Array[Byte],
  lit_len : Int,
  literals_block_type : UInt,
) -> Unit raise ZstdError {
  if literals_block_type != 0 && literals_block_type != 1 {
    raise CorruptionDetected
  }
  if lit_len < 0 || lit_len > 131072 {
    raise CorruptionDetected
  }
  if lit_len <= 31 {
    out.push(
      ((lit_len.reinterpret_as_uint() << 3) + literals_block_type).to_byte(),
    )
  } else if lit_len <= 4095 {
    out.push(
      (((lit_len & 0xF).reinterpret_as_uint() << 4) + 0x04 + literals_block_type).to_byte(),
    )
    out.push(((lit_len >> 4).reinterpret_as_uint() & 0xFF).to_byte())
  } else {
    out.push(
      (((lit_len & 0xF).reinterpret_as_uint() << 4) + 0x0C + literals_block_type).to_byte(),
    )
    out.push(((lit_len >> 4).reinterpret_as_uint() & 0xFF).to_byte())
    out.push(((lit_len >> 12).reinterpret_as_uint() & 0xFF).to_byte())
  }
}

///|
fn append_raw_literals_section(
  out : Array[Byte],
  literals : Bytes,
) -> Unit raise ZstdError {
  let lit_len = literals.length()
  append_literals_header(out, lit_len, 0)
  append_bytes(out, literals, 0, lit_len)
}

///|
fn append_rle_literals_section(
  out : Array[Byte],
  literals : Bytes,
) -> Unit raise ZstdError {
  let lit_len = literals.length()
  if lit_len <= 0 {
    raise CorruptionDetected
  }
  append_literals_header(out, lit_len, 1)
  out.push(literals[0])
}

///|
fn is_single_value_literals(literals : Bytes) -> Bool {
  let lit_len = literals.length()
  if lit_len <= 1 {
    return false
  }
  let first = literals[0]
  let mut i = 1
  while i < lit_len {
    if literals[i] != first {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn append_best_literals_section(
  out : Array[Byte],
  literals : Bytes,
) -> Unit raise ZstdError {
  if is_single_value_literals(literals) {
    append_rle_literals_section(out, literals)
  } else {
    append_raw_literals_section(out, literals)
  }
}

///|
fn build_literals_only_payload(
  src : Bytes,
  start : Int,
  block_len : Int,
  level : Int,
) -> Bytes raise ZstdError {
  if level < 10 || block_len < 32 {
    return b""
  }
  if start < 0 || block_len <= 0 || start + block_len > src.length() {
    return b""
  }
  let literals : Array[Byte] = Array::new()
  append_bytes(literals, src, start, block_len)

  let payload : Array[Byte] = Array::new()
  append_best_literals_section(payload, Bytes::from_array(literals))
  append_sequence_count(payload, 0)
  let encoded = Bytes::from_array(payload)
  if encoded.length() >= block_len {
    return b""
  }
  encoded
}

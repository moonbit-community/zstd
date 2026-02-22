///|
fn bytes_equal(lhs : Bytes, rhs : Bytes) -> Bool {
  if lhs.length() != rhs.length() {
    return false
  }
  let mut i = 0
  while i < lhs.length() {
    if lhs[i] != rhs[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn bytes_slice(src : Bytes, start : Int, len : Int) -> Bytes {
  if start < 0 || len < 0 || start + len > src.length() {
    return b""
  }
  let out : Array[Byte] = Array::new()
  append_bytes(out, src, start, len)
  Bytes::from_array(out)
}

///|
fn parse_single_stream_compressed_literals_header(
  payload : Bytes,
) -> (Bool, UInt, Int, Int, Int, Int) {
  if payload.length() < 4 {
    return (false, 0, 0, 0, 0, 0)
  }
  let byte0 = payload[0].to_uint()
  let literals_block_type = byte0 & 0x3
  if literals_block_type != 2 && literals_block_type != 3 {
    return (false, 0, 0, 0, 0, 0)
  }
  let size_format = (byte0 >> 2) & 0x3
  if size_format != 0 {
    return (false, 0, 0, 0, 0, 0)
  }
  let lhc = payload[0].to_uint() +
    (payload[1].to_uint() << 8) +
    (payload[2].to_uint() << 16)
  let lit_size = ((lhc >> 4) & 0x3FF).reinterpret_as_int()
  let lit_c_size = ((lhc >> 14) & 0x3FF).reinterpret_as_int()
  let header_size = 3
  let payload_pos = header_size
  let payload_end = payload_pos + lit_c_size
  if lit_size < 0 || lit_c_size <= 0 || payload_end > payload.length() {
    return (false, 0, 0, 0, 0, 0)
  }
  (true, literals_block_type, lit_size, lit_c_size, payload_pos, payload_end)
}

///|
fn rewrite_literals_section_to_treeless_if_repeat(
  payload : Bytes,
  prev_huf_valid : Ref[Bool],
  prev_huf_tree_desc : Ref[Bytes],
) -> Bytes {
  let (ok, literals_block_type, lit_size, lit_c_size, payload_pos, payload_end) = parse_single_stream_compressed_literals_header(
    payload,
  )
  if !ok || literals_block_type == 3 {
    return payload
  }

  let tree_result = try? read_huffman_tree_description(
    payload, payload_pos, payload_end,
  )
  let (tree_size, _, _, _, _) = match tree_result {
    Ok(v) => v
    Err(_) => return payload
  }
  if tree_size <= 0 || payload_pos + tree_size > payload_end {
    return payload
  }
  let tree_desc = bytes_slice(payload, payload_pos, tree_size)
  if tree_desc.length() != tree_size {
    return payload
  }

  if !prev_huf_valid.val {
    prev_huf_valid.val = true
    prev_huf_tree_desc.val = tree_desc
    return payload
  }
  if !bytes_equal(prev_huf_tree_desc.val, tree_desc) {
    prev_huf_tree_desc.val = tree_desc
    return payload
  }

  let bitstream_size = lit_c_size - tree_size
  if bitstream_size <= 0 {
    return payload
  }
  let rewritten : Array[Byte] = Array::new()
  let new_header = ((lit_size.reinterpret_as_uint() & 0x3FF) << 4) +
    ((bitstream_size.reinterpret_as_uint() & 0x3FF) << 14) +
    3
  append_u24_le(rewritten, new_header)
  append_bytes(rewritten, payload, payload_pos + tree_size, bitstream_size)
  append_bytes(rewritten, payload, payload_end, payload.length() - payload_end)
  Bytes::from_array(rewritten)
}

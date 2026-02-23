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
fn parse_compressed_literals_header(
  payload : Bytes,
) -> (Bool, UInt, UInt, Int, Int, Int, Int) {
  if payload.length() < 4 {
    return (false, 0, 0, 0, 0, 0, 0)
  }
  let byte0 = payload[0].to_uint()
  let literals_block_type = byte0 & 0x3
  if literals_block_type != 2 && literals_block_type != 3 {
    return (false, 0, 0, 0, 0, 0, 0)
  }
  let size_format = (byte0 >> 2) & 0x3
  let lhc = payload[0].to_uint() +
    (payload[1].to_uint() << 8) +
    (payload[2].to_uint() << 16) +
    (payload[3].to_uint() << 24)
  let (header_size, lit_size, lit_c_size) = if size_format == 0 ||
    size_format == 1 {
    (
      3,
      ((lhc >> 4) & 0x3FF).reinterpret_as_int(),
      ((lhc >> 14) & 0x3FF).reinterpret_as_int(),
    )
  } else if size_format == 2 {
    (
      4,
      ((lhc >> 4) & 0x3FFF).reinterpret_as_int(),
      (lhc >> 18).reinterpret_as_int(),
    )
  } else if size_format == 3 {
    if payload.length() < 5 {
      return (false, 0, 0, 0, 0, 0, 0)
    }
    let b4 = payload[4].to_uint()
    (
      5,
      ((lhc >> 4) & 0x3FFFF).reinterpret_as_int(),
      ((lhc >> 22) + (b4 << 10)).reinterpret_as_int(),
    )
  } else {
    return (false, 0, 0, 0, 0, 0, 0)
  }
  let payload_pos = header_size
  let payload_end = payload_pos + lit_c_size
  if lit_size < 0 ||
    lit_c_size <= 0 ||
    (size_format != 0 && lit_size < 6) ||
    payload_end > payload.length() {
    return (false, 0, 0, 0, 0, 0, 0)
  }
  (
    true, literals_block_type, size_format, lit_size, lit_c_size, payload_pos, payload_end,
  )
}

///|
fn build_codes_from_decode_tree(
  max_bits : Int,
  left : Array[Int],
  right : Array[Int],
  symbol : Array[Int],
) -> (Bool, Array[UInt], Array[Int]) {
  if max_bits <= 0 || symbol.length() == 0 {
    return (false, Array::new(), Array::new())
  }
  let codes = Array::make(256, (0 : UInt))
  let nb_bits = Array::make(256, 0)
  let stack_node : Array[Int] = Array::new()
  let stack_code : Array[UInt] = Array::new()
  let stack_depth : Array[Int] = Array::new()
  stack_node.push(0)
  stack_code.push((0 : UInt))
  stack_depth.push(0)
  let mut assigned = 0
  while stack_node.length() > 0 {
    let top = stack_node.length() - 1
    let node = stack_node[top]
    let code = stack_code[top]
    let depth = stack_depth[top]
    ignore(stack_node.pop())
    ignore(stack_code.pop())
    ignore(stack_depth.pop())
    if node < 0 || node >= symbol.length() || depth > max_bits {
      return (false, Array::new(), Array::new())
    }
    let value = symbol[node]
    if value >= 0 {
      if value >= 256 || depth <= 0 {
        return (false, Array::new(), Array::new())
      }
      codes[value] = code
      nb_bits[value] = depth
      assigned = assigned + 1
    } else {
      let l = left[node]
      let r = right[node]
      if l == -1 && r == -1 {
        return (false, Array::new(), Array::new())
      }
      if r != -1 {
        stack_node.push(r)
        stack_code.push((code << 1) + 1)
        stack_depth.push(depth + 1)
      }
      if l != -1 {
        stack_node.push(l)
        stack_code.push(code << 1)
        stack_depth.push(depth + 1)
      }
    }
  }
  if assigned <= 0 {
    return (false, Array::new(), Array::new())
  }
  (true, codes, nb_bits)
}

///|
fn build_treeless_literals_section_with_stream_payload(
  lit_len : Int,
  stream_payload : Bytes,
  single_stream : Bool,
) -> Bytes {
  if lit_len <= 0 || stream_payload.length() == 0 {
    return b""
  }
  let lit_c_size = stream_payload.length()
  let literals_block_type : UInt = 3
  let out : Array[Byte] = Array::new()
  if single_stream {
    if lit_len > 1023 || lit_c_size > 1023 {
      return b""
    }
    let header = ((lit_len.reinterpret_as_uint() & 0x3FF) << 4) +
      ((lit_c_size.reinterpret_as_uint() & 0x3FF) << 14) +
      literals_block_type
    append_u24_le(out, header)
  } else if lit_len >= 6 && lit_len <= 1023 && lit_c_size <= 1023 {
    let size_format_1 : UInt = 1
    let header = ((lit_len.reinterpret_as_uint() & 0x3FF) << 4) +
      ((lit_c_size.reinterpret_as_uint() & 0x3FF) << 14) +
      (size_format_1 << 2) +
      literals_block_type
    append_u24_le(out, header)
  } else if lit_len <= 0x3FFF && lit_c_size <= 0x3FFF {
    let size_format_2 : UInt = 2
    let header = ((lit_len.reinterpret_as_uint() & 0x3FFF) << 4) +
      ((lit_c_size.reinterpret_as_uint() & 0x3FFF) << 18) +
      (size_format_2 << 2) +
      literals_block_type
    append_u32_le(out, header)
  } else if lit_len <= 0x3FFFF && lit_c_size <= 0x3FFFF {
    let size_format_3 : UInt = 3
    let lit_c_low = lit_c_size & 0x3FF
    let lit_c_high = lit_c_size >> 10
    if lit_c_high < 0 || lit_c_high > 0xFF {
      return b""
    }
    let header = ((lit_len.reinterpret_as_uint() & 0x3FFFF) << 4) +
      ((lit_c_low.reinterpret_as_uint() & 0x3FF) << 22) +
      (size_format_3 << 2) +
      literals_block_type
    append_u32_le(out, header)
    out.push(lit_c_high.reinterpret_as_uint().to_byte())
  } else {
    return b""
  }
  append_bytes(out, stream_payload, 0, stream_payload.length())
  Bytes::from_array(out)
}

///|
fn append_treeless_literals_header_with_size_format(
  out : Array[Byte],
  size_format : UInt,
  lit_size : Int,
  lit_c_size : Int,
) -> Bool {
  let literals_block_type : UInt = 3
  if size_format == 0 || size_format == 1 {
    if lit_size > 1023 || lit_c_size > 1023 {
      return false
    }
    if size_format == 1 && lit_size < 6 {
      return false
    }
    let header = ((lit_size.reinterpret_as_uint() & 0x3FF) << 4) +
      ((lit_c_size.reinterpret_as_uint() & 0x3FF) << 14) +
      (size_format << 2) +
      literals_block_type
    append_u24_le(out, header)
    return true
  }
  if size_format == 2 {
    if lit_size > 0x3FFF || lit_c_size > 0x3FFF {
      return false
    }
    let header = ((lit_size.reinterpret_as_uint() & 0x3FFF) << 4) +
      ((lit_c_size.reinterpret_as_uint() & 0x3FFF) << 18) +
      (size_format << 2) +
      literals_block_type
    append_u32_le(out, header)
    return true
  }
  if size_format == 3 {
    if lit_size > 0x3FFFF || lit_c_size > 0x3FFFF {
      return false
    }
    let lit_c_low = lit_c_size & 0x3FF
    let lit_c_high = lit_c_size >> 10
    if lit_c_high < 0 || lit_c_high > 0xFF {
      return false
    }
    let header = ((lit_size.reinterpret_as_uint() & 0x3FFFF) << 4) +
      ((lit_c_low.reinterpret_as_uint() & 0x3FF) << 22) +
      (size_format << 2) +
      literals_block_type
    append_u32_le(out, header)
    out.push(lit_c_high.reinterpret_as_uint().to_byte())
    return true
  }
  false
}

///|
fn rewrite_literals_section_to_treeless_if_repeat(
  payload : Bytes,
  prev_huf_valid : Ref[Bool],
  prev_huf_tree_desc : Ref[Bytes],
) -> Bytes {
  let (
    ok,
    literals_block_type,
    size_format,
    lit_size,
    lit_c_size,
    payload_pos,
    payload_end,
  ) = parse_compressed_literals_header(payload)
  if !ok || literals_block_type == 3 {
    return payload
  }

  let tree_result = try? read_huffman_tree_description(
    payload, payload_pos, payload_end,
  )
  let (tree_size, cur_max_bits, cur_left, cur_right, cur_symbol) = match
    tree_result {
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
    let literals_result = if size_format == 0 {
      try? decode_huffman_single_stream(
        payload,
        payload_pos + tree_size,
        payload_end,
        lit_size,
        cur_max_bits,
        cur_left,
        cur_right,
        cur_symbol,
      )
    } else {
      try? decode_huffman_four_streams(
        payload,
        payload_pos + tree_size,
        payload_end,
        lit_size,
        cur_max_bits,
        cur_left,
        cur_right,
        cur_symbol,
      )
    }
    let literals = match literals_result {
      Ok(v) => v
      Err(_) => {
        prev_huf_tree_desc.val = tree_desc
        return payload
      }
    }
    let prev_tree_result = try? read_huffman_tree_description(
      prev_huf_tree_desc.val,
      0,
      prev_huf_tree_desc.val.length(),
    )
    let (ok_codes, codes, nb_bits) = match prev_tree_result {
      Ok((_, prev_max_bits, prev_left, prev_right, prev_symbol)) =>
        build_codes_from_decode_tree(
          prev_max_bits, prev_left, prev_right, prev_symbol,
        )
      Err(_) => (false, Array::new(), Array::new())
    }
    if !ok_codes {
      prev_huf_tree_desc.val = tree_desc
      return payload
    }
    let single_stream_payload = encode_literals_huffman_single_stream(
      literals, codes, nb_bits,
    )
    let four_stream_payload = encode_literals_huffman_four_stream(
      literals, codes, nb_bits,
    )
    let single_section = build_treeless_literals_section_with_stream_payload(
      lit_size, single_stream_payload, true,
    )
    let four_section = build_treeless_literals_section_with_stream_payload(
      lit_size, four_stream_payload, false,
    )
    let chosen = if single_section.length() == 0 {
      four_section
    } else if four_section.length() == 0 {
      single_section
    } else if four_section.length() <= single_section.length() {
      four_section
    } else {
      single_section
    }
    if chosen.length() == 0 {
      prev_huf_tree_desc.val = tree_desc
      return payload
    }
    let rewritten : Array[Byte] = Array::new()
    append_bytes(rewritten, chosen, 0, chosen.length())
    append_bytes(
      rewritten,
      payload,
      payload_end,
      payload.length() - payload_end,
    )
    let candidate = Bytes::from_array(rewritten)
    if candidate.length() <= payload.length() + 4 {
      return candidate
    }
    prev_huf_tree_desc.val = tree_desc
    return payload
  }

  let bitstream_size = lit_c_size - tree_size
  if bitstream_size <= 0 {
    return payload
  }
  let rewritten : Array[Byte] = Array::new()
  if !append_treeless_literals_header_with_size_format(
      rewritten, size_format, lit_size, bitstream_size,
    ) {
    return payload
  }
  append_bytes(rewritten, payload, payload_pos + tree_size, bitstream_size)
  append_bytes(rewritten, payload, payload_end, payload.length() - payload_end)
  let candidate = Bytes::from_array(rewritten)
  if size_format == 0 && lit_size >= 6 {
    let (ok_codes, codes, nb_bits) = build_codes_from_decode_tree(
      cur_max_bits, cur_left, cur_right, cur_symbol,
    )
    if ok_codes {
      let literals_result = try? decode_huffman_single_stream(
        payload,
        payload_pos + tree_size,
        payload_end,
        lit_size,
        cur_max_bits,
        cur_left,
        cur_right,
        cur_symbol,
      )
      match literals_result {
        Ok(literals) => {
          let four_stream_payload = encode_literals_huffman_four_stream(
            literals, codes, nb_bits,
          )
          let four_section = build_treeless_literals_section_with_stream_payload(
            lit_size, four_stream_payload, false,
          )
          if four_section.length() > 0 {
            let rewritten4 : Array[Byte] = Array::new()
            append_bytes(rewritten4, four_section, 0, four_section.length())
            append_bytes(
              rewritten4,
              payload,
              payload_end,
              payload.length() - payload_end,
            )
            let candidate4 = Bytes::from_array(rewritten4)
            if candidate4.length() <= candidate.length() + 2 {
              return candidate4
            }
          }
        }
        Err(_) => ()
      }
    }
  }
  candidate
}

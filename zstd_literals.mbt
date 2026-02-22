///|
fn decode_literals_section_minimal(
  src : Bytes,
  start : Int,
  end_pos : Int,
  prev_huf_valid : Ref[Bool],
  prev_huf_max_bits : Ref[Int],
  prev_huf_left : Ref[Array[Int]],
  prev_huf_right : Ref[Array[Int]],
  prev_huf_symbol : Ref[Array[Int]],
) -> (Int, Bytes) raise ZstdError {
  if start >= end_pos {
    raise CorruptionDetected
  }
  let byte0 = src[start].to_uint()
  let literals_block_type = byte0 & 0x3
  let size_format = (byte0 >> 2) & 0x3

  if literals_block_type == 0 || literals_block_type == 1 {
    let (header_size, regenerated_size) = match size_format {
      0 => (1, byte0 >> 3)
      1 => {
        if start + 2 > end_pos {
          raise SrcSizeWrong
        }
        let b1 = src[start + 1].to_uint()
        (2, (byte0 >> 4) + (b1 << 4))
      }
      2 => (1, byte0 >> 3)
      3 => {
        if start + 3 > end_pos {
          raise SrcSizeWrong
        }
        let b1 = src[start + 1].to_uint()
        let b2 = src[start + 2].to_uint()
        (3, (byte0 >> 4) + (b1 << 4) + (b2 << 12))
      }
      _ => raise CorruptionDetected
    }
    let data_pos = start + header_size
    let regen_len = regenerated_size.reinterpret_as_int()
    let literals : Array[Byte] = Array::new()

    if literals_block_type == 0 {
      if data_pos + regen_len > end_pos {
        raise SrcSizeWrong
      }
      append_bytes(literals, src, data_pos, regen_len)
      (data_pos + regen_len, Bytes::from_array(literals))
    } else if regen_len == 0 {
      (data_pos, Bytes::from_array(literals))
    } else {
      if data_pos + 1 > end_pos {
        raise SrcSizeWrong
      }
      let value = src[data_pos]
      let mut i = 0
      while i < regen_len {
        literals.push(value)
        i = i + 1
      }
      (data_pos + 1, Bytes::from_array(literals))
    }
  } else if literals_block_type == 2 || literals_block_type == 3 {
    if start + 4 > end_pos {
      raise SrcSizeWrong
    }
    let lhc = read_u32_le(src, start)
    let single_stream = size_format == 0
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
    } else {
      if start + 5 > end_pos {
        raise SrcSizeWrong
      }
      let b4 = src[start + 4].to_uint()
      (
        5,
        ((lhc >> 4) & 0x3FFFF).reinterpret_as_int(),
        ((lhc >> 22) + (b4 << 10)).reinterpret_as_int(),
      )
    }

    if lit_size < 0 || lit_c_size <= 0 {
      raise CorruptionDetected
    }
    if !single_stream && lit_size < 6 {
      raise CorruptionDetected
    }

    let payload_pos = start + header_size
    if payload_pos + lit_c_size > end_pos {
      raise CorruptionDetected
    }
    let payload_end = payload_pos + lit_c_size

    let (max_bits, left, right, symbol, stream_pos) = if literals_block_type ==
      2 {
      let (tree_size, tree_max_bits, tree_left, tree_right, tree_symbol) = read_huffman_tree_description(
        src, payload_pos, payload_end,
      )

      prev_huf_valid.val = true
      prev_huf_max_bits.val = tree_max_bits
      prev_huf_left.val = tree_left
      prev_huf_right.val = tree_right
      prev_huf_symbol.val = tree_symbol
      (
        tree_max_bits,
        tree_left,
        tree_right,
        tree_symbol,
        payload_pos + tree_size,
      )
    } else {
      if !prev_huf_valid.val {
        raise CorruptionDetected
      }
      (
        prev_huf_max_bits.val,
        prev_huf_left.val,
        prev_huf_right.val,
        prev_huf_symbol.val,
        payload_pos,
      )
    }

    if stream_pos > payload_end {
      raise CorruptionDetected
    }
    let literals = if single_stream {
      decode_huffman_single_stream(
        src, stream_pos, payload_end, lit_size, max_bits, left, right, symbol,
      )
    } else {
      decode_huffman_four_streams(
        src, stream_pos, payload_end, lit_size, max_bits, left, right, symbol,
      )
    }
    (payload_end, literals)
  } else {
    raise CorruptionDetected
  }
}

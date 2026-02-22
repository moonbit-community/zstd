///|
fn payload_sequence_modes_offset(payload : Bytes) -> Int {
  let seq_count_pos = payload_sequence_count_offset(payload)
  if seq_count_pos < 0 {
    return -1
  }
  let seq0 = payload[seq_count_pos].to_uint()
  let seq_count_header_len = if seq0 < 128 {
    1
  } else if seq0 < 255 {
    2
  } else {
    3
  }
  let modes_pos = seq_count_pos + seq_count_header_len
  if modes_pos >= payload.length() {
    return -1
  }
  modes_pos
}

///|
fn payload_sequence_count_header_len(
  payload : Bytes,
  seq_count_pos : Int,
) -> Int {
  if seq_count_pos < 0 || seq_count_pos >= payload.length() {
    return -1
  }
  let seq0 = payload[seq_count_pos].to_uint()
  if seq0 == 0 {
    return -1
  }
  if seq0 < 128 {
    1
  } else if seq0 < 255 {
    2
  } else {
    3
  }
}

///|
fn payload_sequence_count_offset(payload : Bytes) -> Int {
  if payload.length() == 0 {
    return -1
  }
  let lit_desc = payload[0].to_uint()
  if (lit_desc & 0x3) != 0 {
    return -1
  }
  let size_format = (lit_desc >> 2) & 0x3
  let (lit_header_size, lit_len) = if size_format == 0 {
    (1, (lit_desc >> 3).reinterpret_as_int())
  } else if size_format == 1 {
    if payload.length() < 2 {
      return -1
    }
    (2, ((lit_desc >> 4) + (payload[1].to_uint() << 4)).reinterpret_as_int())
  } else if size_format == 3 {
    if payload.length() < 3 {
      return -1
    }
    (
      3,
      ((lit_desc >> 4) +
      (payload[1].to_uint() << 4) +
      (payload[2].to_uint() << 12)).reinterpret_as_int(),
    )
  } else {
    return -1
  }
  let seq_count_pos = lit_header_size + lit_len
  if seq_count_pos >= payload.length() {
    return -1
  }
  let seq0 = payload[seq_count_pos].to_uint()
  if seq0 == 0 {
    return -1
  }
  seq_count_pos
}

///|
fn copy_bytes_range(
  src : Bytes,
  start : Int,
  len : Int,
) -> Bytes raise ZstdError {
  ensure_range(src.length(), start, len)
  let out : Array[Byte] = Array::new()
  append_bytes(out, src, start, len)
  Bytes::from_array(out)
}

///|
fn parse_sequence_source_header(
  payload : Bytes,
  pos : Int,
  mode : UInt,
  max_symbol_limit : Int,
  table_log_max : Int,
) -> (Bytes, Int) raise ZstdError {
  if mode == 0 || mode == 3 {
    return (b"", pos)
  }
  if mode == 1 {
    let header = copy_bytes_range(payload, pos, 1)
    return (header, pos + 1)
  }
  if mode != 2 {
    raise CorruptionDetected
  }
  let (header_size, _, _, _) = read_fse_ncount_header(
    payload,
    pos,
    payload.length(),
    max_symbol_limit,
    table_log_max,
  )
  let header = copy_bytes_range(payload, pos, header_size)
  (header, pos + header_size)
}

///|
fn parse_sequence_mode_sources(
  payload : Bytes,
) -> (Int, UInt, UInt, UInt, Bytes, Bytes, Bytes, Int) raise ZstdError {
  let seq_count_pos = payload_sequence_count_offset(payload)
  let seq_count_header_len = payload_sequence_count_header_len(
    payload, seq_count_pos,
  )
  if seq_count_pos < 0 || seq_count_header_len <= 0 {
    raise CorruptionDetected
  }
  let modes_pos = seq_count_pos + seq_count_header_len
  if modes_pos < 0 || modes_pos >= payload.length() {
    raise CorruptionDetected
  }
  let modes = payload[modes_pos].to_uint()
  let ll_mode = (modes >> 6) & 0x3
  let off_mode = (modes >> 4) & 0x3
  let ml_mode = (modes >> 2) & 0x3
  let mut pos = modes_pos + 1

  let (ll_source, p1) = parse_sequence_source_header(
    payload, pos, ll_mode, 35, 9,
  )
  pos = p1
  let (off_source, p2) = parse_sequence_source_header(
    payload, pos, off_mode, 31, 8,
  )
  pos = p2
  let (ml_source, p3) = parse_sequence_source_header(
    payload, pos, ml_mode, 52, 9,
  )
  pos = p3

  (modes_pos, ll_mode, off_mode, ml_mode, ll_source, off_source, ml_source, pos)
}

///|
fn has_compressed_header(header : Bytes) -> Bool {
  header.length() > 0
}

///|
fn update_prev_compressed_header_state(
  mode : UInt,
  mode0 : UInt,
  source : Bytes,
  prev_header : Ref[Bytes],
) -> Unit {
  if mode == 0 || mode == 1 {
    prev_header.val = b""
    return
  }
  if mode == 2 || (mode == 3 && mode0 == 2) {
    prev_header.val = source
  }
}

///|
fn maybe_rewrite_sequence_modes_to_repeat(
  payload : Bytes,
  prev_rle_valid : Ref[Bool],
  prev_ll_code : Ref[UInt],
  prev_off_code : Ref[UInt],
  prev_ml_code : Ref[UInt],
  prev_predefined_valid : Ref[Bool],
  prev_compressed_valid : Ref[Bool],
  prev_ll_header : Ref[Bytes],
  prev_off_header : Ref[Bytes],
  prev_ml_header : Ref[Bytes],
) -> Bytes {
  let modes_pos = payload_sequence_modes_offset(payload)
  if modes_pos < 0 {
    return payload
  }
  let modes = payload[modes_pos].to_uint()
  if modes == 0 {
    if prev_predefined_valid.val {
      let out : Array[Byte] = Array::new()
      append_bytes(out, payload, 0, modes_pos)
      out.push((0xFC : UInt).to_byte()) // all repeat sequence modes
      append_bytes(
        out,
        payload,
        modes_pos + 1,
        payload.length() - (modes_pos + 1),
      )
      return Bytes::from_array(out)
    }
    prev_predefined_valid.val = true
    prev_rle_valid.val = false
    prev_compressed_valid.val = false
    prev_ll_header.val = b""
    prev_off_header.val = b""
    prev_ml_header.val = b""
    return payload
  }
  if modes == 0x54 {
    if modes_pos + 3 >= payload.length() {
      return payload
    }
    let ll_code = payload[modes_pos + 1].to_uint()
    let off_code = payload[modes_pos + 2].to_uint()
    let ml_code = payload[modes_pos + 3].to_uint()
    if prev_rle_valid.val &&
      ll_code == prev_ll_code.val &&
      off_code == prev_off_code.val &&
      ml_code == prev_ml_code.val {
      let out : Array[Byte] = Array::new()
      append_bytes(out, payload, 0, modes_pos)
      out.push((0xFC : UInt).to_byte()) // all repeat sequence modes
      append_bytes(
        out,
        payload,
        modes_pos + 4,
        payload.length() - (modes_pos + 4),
      )
      return Bytes::from_array(out)
    }
    prev_rle_valid.val = true
    prev_predefined_valid.val = false
    prev_compressed_valid.val = false
    prev_ll_code.val = ll_code
    prev_off_code.val = off_code
    prev_ml_code.val = ml_code
    prev_ll_header.val = b""
    prev_off_header.val = b""
    prev_ml_header.val = b""
    return payload
  }
  if modes == 0xFC {
    return payload
  }
  let parsed = try? parse_sequence_mode_sources(payload)
  match parsed {
    Ok(
      (
        mode_pos,
        ll_mode0,
        off_mode0,
        ml_mode0,
        ll_source,
        off_source,
        ml_source,
        bitstream_start,
      )
    ) => {
      let ll_mode : UInt = if ll_mode0 == 2 &&
        has_compressed_header(prev_ll_header.val) &&
        ll_source == prev_ll_header.val {
        3
      } else {
        ll_mode0
      }
      let off_mode : UInt = if off_mode0 == 2 &&
        has_compressed_header(prev_off_header.val) &&
        off_source == prev_off_header.val {
        3
      } else {
        off_mode0
      }
      let ml_mode : UInt = if ml_mode0 == 2 &&
        has_compressed_header(prev_ml_header.val) &&
        ml_source == prev_ml_header.val {
        3
      } else {
        ml_mode0
      }
      let new_modes = (ll_mode << 6) + (off_mode << 4) + (ml_mode << 2)
      let rewritten = if new_modes != modes {
        let out : Array[Byte] = Array::new()
        append_bytes(out, payload, 0, mode_pos)
        out.push(new_modes.to_byte())
        if ll_mode == 1 || ll_mode == 2 {
          append_bytes(out, ll_source, 0, ll_source.length())
        }
        if off_mode == 1 || off_mode == 2 {
          append_bytes(out, off_source, 0, off_source.length())
        }
        if ml_mode == 1 || ml_mode == 2 {
          append_bytes(out, ml_source, 0, ml_source.length())
        }
        append_bytes(
          out,
          payload,
          bitstream_start,
          payload.length() - bitstream_start,
        )
        Bytes::from_array(out)
      } else {
        payload
      }

      prev_rle_valid.val = false
      prev_predefined_valid.val = false
      update_prev_compressed_header_state(
        ll_mode, ll_mode0, ll_source, prev_ll_header,
      )
      update_prev_compressed_header_state(
        off_mode, off_mode0, off_source, prev_off_header,
      )
      update_prev_compressed_header_state(
        ml_mode, ml_mode0, ml_source, prev_ml_header,
      )
      prev_compressed_valid.val = has_compressed_header(prev_ll_header.val) ||
        has_compressed_header(prev_off_header.val) ||
        has_compressed_header(prev_ml_header.val)
      return rewritten
    }
    Err(_) => {
      prev_rle_valid.val = false
      prev_predefined_valid.val = false
      prev_compressed_valid.val = false
      prev_ll_header.val = b""
      prev_off_header.val = b""
      prev_ml_header.val = b""
      return payload
    }
  }
}

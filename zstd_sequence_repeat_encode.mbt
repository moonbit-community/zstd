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
fn maybe_rewrite_sequence_modes_to_repeat(
  payload : Bytes,
  prev_rle_valid : Ref[Bool],
  prev_ll_code : Ref[UInt],
  prev_off_code : Ref[UInt],
  prev_ml_code : Ref[UInt],
  prev_predefined_valid : Ref[Bool],
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
    prev_ll_code.val = ll_code
    prev_off_code.val = off_code
    prev_ml_code.val = ml_code
    return payload
  }
  if modes == 0xFC {
    return payload
  }
  prev_rle_valid.val = false
  prev_predefined_valid.val = false
  payload
}

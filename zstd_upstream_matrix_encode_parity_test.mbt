///|
fn matrix_l9_options(checksum : Bool) -> CompressOptions {
  default_compress_options(level=9).with_checksum(checksum)
}

///|
fn assert_frame_parity(
  name : String,
  got : Bytes,
  expected : Bytes,
) -> Unit raise Error {
  if got == expected {
    return
  }
  let min_len = if got.length() < expected.length() {
    got.length()
  } else {
    expected.length()
  }
  let mut diff = 0
  while diff < min_len && got[diff] == expected[diff] {
    diff = diff + 1
  }
  if diff < min_len {
    fail(
      "matrix parity " +
      name +
      " mismatch: got_len=" +
      got.length().to_string() +
      ", expected_len=" +
      expected.length().to_string() +
      ", first_diff=" +
      diff.to_string() +
      ", got=0x" +
      got[diff].to_uint().to_string(radix=16) +
      ", expected=0x" +
      expected[diff].to_uint().to_string(radix=16) +
      ", got_blocks=" +
      frame_block_summary(got) +
      ", got_first_block=" +
      first_block_payload_brief(got) +
      ", expected_blocks=" +
      frame_block_summary(expected) +
      ", expected_first_block=" +
      first_block_payload_brief(expected),
    )
  } else {
    fail(
      "matrix parity " +
      name +
      " mismatch: prefix equal, got_len=" +
      got.length().to_string() +
      ", expected_len=" +
      expected.length().to_string() +
      ", got_blocks=" +
      frame_block_summary(got) +
      ", got_first_block=" +
      first_block_payload_brief(got) +
      ", expected_blocks=" +
      frame_block_summary(expected) +
      ", expected_first_block=" +
      first_block_payload_brief(expected),
    )
  }
}

///|
fn read_u24_le_matrix_diag(src : Bytes, pos : Int) -> Int {
  src[pos].to_int() +
  (src[pos + 1].to_int() << 8) +
  (src[pos + 2].to_int() << 16)
}

///|
fn frame_block_summary(frame : Bytes) -> String {
  if frame.length() < 10 {
    return "short"
  }
  let descriptor = frame[4].to_uint()
  let single_segment = ((descriptor >> 5) & 1) == (1 : UInt)
  let dict_flag = (descriptor & 0x3).reinterpret_as_int()
  let fcs_flag = (descriptor >> 6).reinterpret_as_int()
  let mut pos = 5
  if !single_segment {
    pos = pos + 1
  }
  if dict_flag == 1 {
    pos = pos + 1
  } else if dict_flag == 2 {
    pos = pos + 2
  } else if dict_flag == 3 {
    pos = pos + 4
  }
  let fcs_size = if single_segment {
    if fcs_flag == 0 {
      1
    } else if fcs_flag == 1 {
      2
    } else {
      4
    }
  } else if fcs_flag == 0 {
    0
  } else if fcs_flag == 1 {
    2
  } else {
    4
  }
  pos = pos + fcs_size
  if pos + 3 > frame.length() {
    return "no-block"
  }
  let parts : Array[String] = Array::new()
  let mut i = 0
  let mut cursor = pos
  while i < 4 && cursor + 3 <= frame.length() {
    let raw = read_u24_le_matrix_diag(frame, cursor)
    let last = (raw & 1) == 1
    let block_type = (raw >> 1) & 0x3
    let block_size = raw >> 3
    parts.push(
      i.to_string() +
      ":" +
      block_type.to_string() +
      "/" +
      block_size.to_string() +
      "/" +
      (if last { "L" } else { "N" }),
    )
    cursor = cursor + 3 + block_size
    i = i + 1
    if last {
      i = 4
    }
  }
  let mut joined = ""
  let mut j = 0
  while j < parts.length() {
    if j > 0 {
      joined = joined + ","
    }
    joined = joined + parts[j]
    j = j + 1
  }
  "d=" + descriptor.to_string(radix=16) + ",b=[" + joined + "]"
}

///|
fn frame_first_block_header_pos(frame : Bytes) -> Int {
  if frame.length() < 10 {
    return -1
  }
  let descriptor = frame[4].to_uint()
  let single_segment = ((descriptor >> 5) & 1) == (1 : UInt)
  let dict_flag = (descriptor & 0x3).reinterpret_as_int()
  let fcs_flag = (descriptor >> 6).reinterpret_as_int()
  let mut pos = 5
  if !single_segment {
    pos = pos + 1
  }
  if dict_flag == 1 {
    pos = pos + 1
  } else if dict_flag == 2 {
    pos = pos + 2
  } else if dict_flag == 3 {
    pos = pos + 4
  }
  let fcs_size = if single_segment {
    if fcs_flag == 0 {
      1
    } else if fcs_flag == 1 {
      2
    } else {
      4
    }
  } else if fcs_flag == 0 {
    0
  } else if fcs_flag == 1 {
    2
  } else {
    4
  }
  pos + fcs_size
}

///|
fn parse_seq_count_brief(payload : Bytes, pos : Int) -> (Bool, Int, Int) {
  if pos >= payload.length() {
    return (false, 0, 0)
  }
  let b0 = payload[pos].to_uint().reinterpret_as_int()
  if b0 < 128 {
    return (true, b0, pos + 1)
  }
  if b0 < 255 {
    if pos + 1 >= payload.length() {
      return (false, 0, 0)
    }
    let count = ((b0 - 128) << 8) +
      payload[pos + 1].to_uint().reinterpret_as_int()
    return (true, count, pos + 2)
  }
  if pos + 2 >= payload.length() {
    return (false, 0, 0)
  }
  let rem = payload[pos + 1].to_uint().reinterpret_as_int() +
    (payload[pos + 2].to_uint().reinterpret_as_int() << 8)
  (true, 0x7F00 + rem, pos + 3)
}

///|
fn first_block_payload_brief(frame : Bytes) -> String {
  let block_header_pos = frame_first_block_header_pos(frame)
  if block_header_pos < 0 || block_header_pos + 3 > frame.length() {
    return "invalid"
  }
  let block_raw = read_u24_le_matrix_diag(frame, block_header_pos)
  let block_type = (block_raw >> 1) & 0x3
  let block_size = block_raw >> 3
  if block_type != 2 {
    return "type=" + block_type.to_string() + ",size=" + block_size.to_string()
  }
  let payload_start = block_header_pos + 3
  let payload_end = payload_start + block_size
  if payload_end > frame.length() || payload_start >= payload_end {
    return "type=2,size=" + block_size.to_string() + ",payload-oob"
  }
  let payload = frame[payload_start:payload_end].to_bytes()
  let h0 = payload[0].to_uint().reinterpret_as_int()
  let lit_type = h0 & 0x3
  let size_format = (h0 >> 2) & 0x3
  let mut lit_regen_size = -1
  let mut lit_comp_size = -1
  let mut lit_header_size = 0
  let mut tree_desc_size = -1
  let mut huf_streams_size = -1
  let mut tree_head = -1
  if lit_type == 0 || lit_type == 1 {
    if size_format == 0 {
      lit_regen_size = h0 >> 3
      lit_header_size = 1
    } else if size_format == 1 {
      if payload.length() < 2 {
        return "type=2,size=" + block_size.to_string() + ",lit-header-oob"
      }
      lit_regen_size = (h0 >> 4) +
        (payload[1].to_uint().reinterpret_as_int() << 4)
      lit_header_size = 2
    } else {
      if payload.length() < 3 {
        return "type=2,size=" + block_size.to_string() + ",lit-header-oob"
      }
      lit_regen_size = (h0 >> 4) +
        (payload[1].to_uint().reinterpret_as_int() << 4) +
        (payload[2].to_uint().reinterpret_as_int() << 12)
      lit_header_size = 3
    }
    lit_comp_size = if lit_type == 1 { 1 } else { lit_regen_size }
  } else {
    if size_format == 0 || size_format == 1 {
      if payload.length() < 3 {
        return "type=2,size=" + block_size.to_string() + ",lit-header-oob"
      }
      let raw24 = read_u24_le_matrix_diag(payload, 0)
      lit_regen_size = (raw24 >> 4) & 0x3FF
      lit_comp_size = (raw24 >> 14) & 0x3FF
      lit_header_size = 3
    } else if size_format == 2 {
      if payload.length() < 4 {
        return "type=2,size=" + block_size.to_string() + ",lit-header-oob"
      }
      let raw32 = payload[0].to_uint().reinterpret_as_int() +
        (payload[1].to_uint().reinterpret_as_int() << 8) +
        (payload[2].to_uint().reinterpret_as_int() << 16) +
        (payload[3].to_uint().reinterpret_as_int() << 24)
      lit_regen_size = (raw32 >> 4) & 0x3FFF
      lit_comp_size = (raw32 >> 18) & 0x3FFF
      lit_header_size = 4
    } else {
      if payload.length() < 5 {
        return "type=2,size=" + block_size.to_string() + ",lit-header-oob"
      }
      let raw32 = payload[0].to_uint().reinterpret_as_int() +
        (payload[1].to_uint().reinterpret_as_int() << 8) +
        (payload[2].to_uint().reinterpret_as_int() << 16) +
        (payload[3].to_uint().reinterpret_as_int() << 24)
      lit_regen_size = (raw32 >> 4) & 0x3FFFF
      let lit_comp_low = (raw32 >> 22) & 0x3FF
      let lit_comp_high = payload[4].to_uint().reinterpret_as_int()
      lit_comp_size = lit_comp_low + (lit_comp_high << 10)
      lit_header_size = 5
    }
    if lit_comp_size > 0 && lit_header_size < payload.length() {
      let huf_desc_header = payload[lit_header_size]
        .to_uint()
        .reinterpret_as_int()
      tree_head = huf_desc_header
      let desc_size = if huf_desc_header < 128 {
        1 + huf_desc_header
      } else {
        let number_of_weights = huf_desc_header - 127
        1 + ((number_of_weights + 1) >> 1)
      }
      if desc_size > 0 && desc_size <= lit_comp_size {
        tree_desc_size = desc_size
        huf_streams_size = lit_comp_size - desc_size
      }
    }
  }
  let seq_count_pos = lit_header_size + lit_comp_size
  let (seq_ok, seq_count, seq_next) = parse_seq_count_brief(
    payload, seq_count_pos,
  )
  let seq_modes = if seq_ok && seq_count > 0 && seq_next < payload.length() {
    payload[seq_next].to_uint().to_string(radix=16)
  } else {
    "none"
  }
  "size=" +
  block_size.to_string() +
  ",lit_type=" +
  lit_type.to_string() +
  ",lit_sf=" +
  size_format.to_string() +
  ",lit_regen=" +
  lit_regen_size.to_string() +
  ",lit_comp=" +
  lit_comp_size.to_string() +
  ",tree_desc=" +
  tree_desc_size.to_string() +
  ",tree_head=" +
  tree_head.to_string() +
  ",tree_kind=" +
  (if tree_head >= 128 {
    "direct"
  } else if tree_head >= 0 {
    "fse"
  } else {
    "na"
  }) +
  ",huf_streams=" +
  huf_streams_size.to_string() +
  ",seq_count=" +
  (if seq_ok { seq_count.to_string() } else { "err" }) +
  ",seq_mode=" +
  seq_modes
}

///|
test "upstream matrix encode byte parity plain level9 default checksum" {
  let frame = compress_with_options(
    rv_up_extra_http_x420_payload(),
    matrix_l9_options(true),
  )
  assert_frame_parity("plain-l9", frame, rv_up_matrix_http_x420_frame_l9())
}

///|
test "upstream matrix encode byte parity plain level9 no-check" {
  let frame = compress_with_options(
    rv_up_extra_http_x420_payload(),
    matrix_l9_options(false),
  )
  assert_frame_parity(
    "plain-l9-nocheck",
    frame,
    rv_up_matrix_http_x420_frame_l9_nocheck(),
  )
}

///|
test "upstream matrix encode byte parity dictionary level9 default checksum" {
  let frame = compress_with_dictionary_and_options(
    rv_up_extra_http_x420_payload(),
    rv_up_gdict_http_dict(),
    matrix_l9_options(true),
  )
  assert_frame_parity("dict-l9", frame, rv_up_matrix_http_x420_dict_frame_l9())
}

///|
test "upstream matrix encode byte parity dictionary level9 no-check" {
  let frame = compress_with_dictionary_and_options(
    rv_up_extra_http_x420_payload(),
    rv_up_gdict_http_dict(),
    matrix_l9_options(false),
  )
  assert_frame_parity(
    "dict-l9-nocheck",
    frame,
    rv_up_matrix_http_x420_dict_frame_l9_nocheck(),
  )
}

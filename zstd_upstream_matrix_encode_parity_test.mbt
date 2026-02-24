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
      ", expected_blocks=" +
      frame_block_summary(expected),
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
      ", expected_blocks=" +
      frame_block_summary(expected),
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
#skip("TODO(zstd-rdl.42): plain level9 matrix encode still diverges from upstream bytes")
test "upstream matrix encode byte parity plain level9 default checksum" {
  let frame = compress_with_options(
    rv_up_extra_http_x420_payload(),
    matrix_l9_options(true),
  )
  assert_frame_parity("plain-l9", frame, rv_up_matrix_http_x420_frame_l9())
}

///|
#skip("TODO(zstd-rdl.42): plain level9 matrix encode still diverges from upstream bytes")
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
#skip("TODO(zstd-rdl.42): dictionary level9 matrix encode still diverges from upstream bytes")
test "upstream matrix encode byte parity dictionary level9 default checksum" {
  let frame = compress_with_dictionary_and_options(
    rv_up_extra_http_x420_payload(),
    rv_up_gdict_http_dict(),
    matrix_l9_options(true),
  )
  assert_frame_parity("dict-l9", frame, rv_up_matrix_http_x420_dict_frame_l9())
}

///|
#skip("TODO(zstd-rdl.42): dictionary level9 matrix encode still diverges from upstream bytes")
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

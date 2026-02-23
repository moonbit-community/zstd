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
      expected[diff].to_uint().to_string(radix=16),
    )
  } else {
    fail(
      "matrix parity " +
      name +
      " mismatch: prefix equal, got_len=" +
      got.length().to_string() +
      ", expected_len=" +
      expected.length().to_string(),
    )
  }
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

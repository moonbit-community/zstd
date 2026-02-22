///|
fn assert_upstream_matrix_plain_vector(
  name : String,
  frame : Bytes,
) -> Unit raise Error {
  let result = try? decompress(frame)
  match result {
    Ok(out) => assert_eq(out, rv_up_extra_http_x420_payload())
    Err(SrcSizeTooLarge(_)) =>
      fail(
        "upstream matrix plain vector " +
        name +
        " decode failed: SrcSizeTooLarge",
      )
    Err(SrcSizeWrong) =>
      fail(
        "upstream matrix plain vector " + name + " decode failed: SrcSizeWrong",
      )
    Err(CorruptionDetected) =>
      fail(
        "upstream matrix plain vector " +
        name +
        " decode failed: CorruptionDetected",
      )
    Err(BoundOverflow) =>
      fail(
        "upstream matrix plain vector " + name + " decode failed: BoundOverflow",
      )
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "upstream matrix plain vector " +
        name +
        " decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail(
        "upstream matrix plain vector " +
        name +
        " decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
fn assert_upstream_matrix_dict_vector(
  name : String,
  frame : Bytes,
) -> Unit raise Error {
  let result = try? decompress_with_dictionary(frame, rv_up_gdict_http_dict())
  match result {
    Ok(out) => assert_eq(out, rv_up_extra_http_x420_payload())
    Err(SrcSizeTooLarge(_)) =>
      fail(
        "upstream matrix dictionary vector " +
        name +
        " decode failed: SrcSizeTooLarge",
      )
    Err(SrcSizeWrong) =>
      fail(
        "upstream matrix dictionary vector " +
        name +
        " decode failed: SrcSizeWrong",
      )
    Err(CorruptionDetected) =>
      fail(
        "upstream matrix dictionary vector " +
        name +
        " decode failed: CorruptionDetected",
      )
    Err(BoundOverflow) =>
      fail(
        "upstream matrix dictionary vector " +
        name +
        " decode failed: BoundOverflow",
      )
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "upstream matrix dictionary vector " +
        name +
        " decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail(
        "upstream matrix dictionary vector " +
        name +
        " decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
test "upstream matrix plain http x420 level9" {
  assert_upstream_matrix_plain_vector(
    "http-x420-l9",
    rv_up_matrix_http_x420_frame_l9(),
  )
}

///|
test "upstream matrix plain http x420 level9 no-check" {
  assert_upstream_matrix_plain_vector(
    "http-x420-l9-nocheck",
    rv_up_matrix_http_x420_frame_l9_nocheck(),
  )
}

///|
test "upstream matrix plain http x420 level9 target1k" {
  assert_upstream_matrix_plain_vector(
    "http-x420-l9-target1k",
    rv_up_matrix_http_x420_frame_l9_t1k(),
  )
}

///|
test "upstream matrix plain http x420 level9 long27" {
  assert_upstream_matrix_plain_vector(
    "http-x420-l9-long27",
    rv_up_matrix_http_x420_frame_l9_long27(),
  )
}

///|
test "upstream matrix dictionary http x420 level9" {
  assert_upstream_matrix_dict_vector(
    "http-x420-dict-l9",
    rv_up_matrix_http_x420_dict_frame_l9(),
  )
}

///|
test "upstream matrix dictionary http x420 level9 no-check" {
  assert_upstream_matrix_dict_vector(
    "http-x420-dict-l9-nocheck",
    rv_up_matrix_http_x420_dict_frame_l9_nocheck(),
  )
}

///|
test "upstream matrix dictionary http x420 level9 target1k" {
  assert_upstream_matrix_dict_vector(
    "http-x420-dict-l9-target1k",
    rv_up_matrix_http_x420_dict_frame_l9_t1k(),
  )
}

///|
test "upstream matrix dictionary http x420 level9 long27" {
  assert_upstream_matrix_dict_vector(
    "http-x420-dict-l9-long27",
    rv_up_matrix_http_x420_dict_frame_l9_long27(),
  )
}

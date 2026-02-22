///|
fn assert_upstream_gdict_http_vector(
  name : String,
  frame : Bytes,
) -> Unit raise Error {
  let result = try? decompress_with_dictionary(frame, rv_up_gdict_http_dict())
  match result {
    Ok(out) => assert_eq(out, rv_up_http_payload())
    Err(SrcSizeTooLarge(_)) =>
      fail("upstream gdict vector " + name + " decode failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) =>
      fail("upstream gdict vector " + name + " decode failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail(
        "upstream gdict vector " + name + " decode failed: CorruptionDetected",
      )
    Err(BoundOverflow) =>
      fail("upstream gdict vector " + name + " decode failed: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "upstream gdict vector " +
        name +
        " decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail(
        "upstream gdict vector " +
        name +
        " decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
test "upstream golden dictionary http level1" {
  assert_upstream_gdict_http_vector("http-dict-l1", rv_up_gdict_http_frame_l1())
}

///|
test "upstream golden dictionary http level19" {
  assert_upstream_gdict_http_vector(
    "http-dict-l19",
    rv_up_gdict_http_frame_l19(),
  )
}

///|
test "upstream golden dictionary http level19 no-check" {
  assert_upstream_gdict_http_vector(
    "http-dict-l19-nocheck",
    rv_up_gdict_http_frame_nocheck_l19(),
  )
}

///|
test "upstream golden dictionary http level19 long27" {
  assert_upstream_gdict_http_vector(
    "http-dict-l19-long27",
    rv_up_gdict_http_frame_long27_l19(),
  )
}

///|
test "upstream golden dictionary dictID mismatch is rejected" {
  let dict = rv_up_gdict_http_dict()
  let bad_dict = Bytes::makei(dict.length(), i => {
    if i == 4 {
      (dict[i].to_uint() ^ 1).to_byte()
    } else {
      dict[i]
    }
  })
  let result = try? decompress_with_dictionary(
    rv_up_gdict_http_frame_l19(),
    bad_dict,
  )
  assert_true(result is Err(CorruptionDetected))
}

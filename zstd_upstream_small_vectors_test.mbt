///|
fn assert_upstream_small_vector(
  name : String,
  frame : Bytes,
  expected : Bytes,
) -> Unit raise Error {
  let result = try? decompress(frame)
  match result {
    Ok(out) => assert_eq(out, expected)
    Err(SrcSizeTooLarge(_)) =>
      fail("upstream small vector " + name + " decode failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) =>
      fail("upstream small vector " + name + " decode failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail(
        "upstream small vector " + name + " decode failed: CorruptionDetected",
      )
    Err(BoundOverflow) =>
      fail("upstream small vector " + name + " decode failed: BoundOverflow")
    Err(UnsupportedFeature(msg)) =>
      fail(
        "upstream small vector " +
        name +
        " decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
test "upstream small vector http level1" {
  assert_upstream_small_vector(
    "http-l1",
    rv_up_http_frame_l1(),
    rv_up_http_payload(),
  )
}

///|
test "upstream small vector http no-check level19" {
  assert_upstream_small_vector(
    "http-l19-nocheck",
    rv_up_http_frame_nocheck_l19(),
    rv_up_http_payload(),
  )
}

///|
test "upstream small vector hcl level1" {
  assert_upstream_small_vector(
    "hcl-l1",
    rv_up_hcl_frame_l1(),
    rv_up_hcl_payload(),
  )
}

///|
test "upstream small vector hcl long27 level19" {
  assert_upstream_small_vector(
    "hcl-long27-l19",
    rv_up_hcl_frame_long27_l19(),
    rv_up_hcl_payload(),
  )
}

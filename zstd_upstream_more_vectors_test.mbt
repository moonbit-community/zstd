///|
fn assert_upstream_large_vector(
  name : String,
  frame : Bytes,
  expected_len : Int,
  prefix64 : Bytes,
  suffix64 : Bytes,
) -> Unit raise Error {
  let result = try? decompress(frame)
  match result {
    Ok(out) => {
      assert_eq(out.length(), expected_len)
      assert_eq(out[:64].to_bytes(), prefix64)
      assert_eq(out[out.length() - 64:].to_bytes(), suffix64)
    }
    Err(SrcSizeTooLarge(_)) =>
      fail("upstream large vector " + name + " decode failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) =>
      fail("upstream large vector " + name + " decode failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail(
        "upstream large vector " + name + " decode failed: CorruptionDetected",
      )
    Err(BoundOverflow) =>
      fail("upstream large vector " + name + " decode failed: BoundOverflow")
    Err(UnsupportedFeature(msg)) =>
      fail(
        "upstream large vector " +
        name +
        " decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
test "upstream golden-compression PR-3517-block-splitter-corruption-test" {
  assert_upstream_large_vector(
    "pr3517-l19",
    rv_up_pr3517_frame_l19(),
    rv_up_pr3517_len(),
    rv_up_pr3517_prefix_64(),
    rv_up_pr3517_suffix_64(),
  )
}

///|
test "upstream golden-compression large-literal-and-match-lengths" {
  assert_upstream_large_vector(
    "llml-l19-nocheck",
    rv_up_llml_frame_nocheck_l19(),
    rv_up_llml_len(),
    rv_up_llml_prefix_64(),
    rv_up_llml_suffix_64(),
  )
}

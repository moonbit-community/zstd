///|
fn assert_real_vector_p03(frame : Bytes) -> Unit raise Error {
  let result = try? decompress_with_dictionary(frame, rv_dict_p03_20260222())
  match result {
    Ok(out) => {
      assert_eq(out.length(), rv_p03_expected_len())
      assert_eq(out[:64].to_bytes(), rv_p03_prefix_64())
      assert_eq(out[out.length() - 64:].to_bytes(), rv_p03_suffix_64())
    }
    Err(SrcSizeTooLarge(_)) =>
      fail("real vector p03 decode failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) => fail("real vector p03 decode failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail("real vector p03 decode failed: CorruptionDetected")
    Err(BoundOverflow) => fail("real vector p03 decode failed: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "real vector p03 decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail("real vector p03 decode failed: UnsupportedFeature " + msg)
  }
}

///|
test "real dictionary vector p03 level1" {
  assert_real_vector_p03(rv_frame_p03_l1())
}

///|
test "real dictionary vector p03 level9" {
  assert_real_vector_p03(rv_frame_p03_l9())
}

///|
test "real dictionary vector p03 level19" {
  assert_real_vector_p03(rv_frame_p03_l19())
}

///|
test "real dictionary vector p03 level19 with checksum" {
  assert_real_vector_p03(rv_frame_p03_chk_l19())
}

///|
test "real dictionary vector p03 level19 without checksum" {
  assert_real_vector_p03(rv_frame_p03_nocheck_l19())
}

///|
test "real dictionary vector p03 long27 level19" {
  assert_real_vector_p03(rv_frame_p03_long27())
}

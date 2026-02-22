///|
fn assert_matrix_case(
  name : String,
  frame : Bytes,
  expected_len : Int,
  expected_prefix_64 : Bytes,
  expected_suffix_64 : Bytes,
) -> Unit raise Error {
  let result = try? decompress_with_dictionary(frame, rv_matrix_dict())
  match result {
    Ok(out) => {
      assert_eq(out.length(), expected_len)
      assert_eq(out[:64].to_bytes(), expected_prefix_64)
      assert_eq(out[out.length() - 64:].to_bytes(), expected_suffix_64)
    }
    Err(SrcSizeTooLarge(_)) =>
      fail("matrix case " + name + " failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) => fail("matrix case " + name + " failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail("matrix case " + name + " failed: CorruptionDetected")
    Err(BoundOverflow) => fail("matrix case " + name + " failed: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "matrix case " +
        name +
        " failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail("matrix case " + name + " failed: UnsupportedFeature " + msg)
  }
}

///|
test "dictionary matrix payload A variants" {
  assert_matrix_case(
    "a-l1",
    rv_matrix_a_frame_l1(),
    rv_matrix_a_len(),
    rv_matrix_a_prefix_64(),
    rv_matrix_a_suffix_64(),
  )
  assert_matrix_case(
    "a-l9",
    rv_matrix_a_frame_l9(),
    rv_matrix_a_len(),
    rv_matrix_a_prefix_64(),
    rv_matrix_a_suffix_64(),
  )
  assert_matrix_case(
    "a-l19",
    rv_matrix_a_frame_l19(),
    rv_matrix_a_len(),
    rv_matrix_a_prefix_64(),
    rv_matrix_a_suffix_64(),
  )
  assert_matrix_case(
    "a-l19-nocheck",
    rv_matrix_a_frame_nocheck_l19(),
    rv_matrix_a_len(),
    rv_matrix_a_prefix_64(),
    rv_matrix_a_suffix_64(),
  )
  assert_matrix_case(
    "a-l19-long27",
    rv_matrix_a_frame_long27_l19(),
    rv_matrix_a_len(),
    rv_matrix_a_prefix_64(),
    rv_matrix_a_suffix_64(),
  )
}

///|
test "dictionary matrix payload B variants" {
  assert_matrix_case(
    "b-l1",
    rv_matrix_b_frame_l1(),
    rv_matrix_b_len(),
    rv_matrix_b_prefix_64(),
    rv_matrix_b_suffix_64(),
  )
  assert_matrix_case(
    "b-l9",
    rv_matrix_b_frame_l9(),
    rv_matrix_b_len(),
    rv_matrix_b_prefix_64(),
    rv_matrix_b_suffix_64(),
  )
  assert_matrix_case(
    "b-l19",
    rv_matrix_b_frame_l19(),
    rv_matrix_b_len(),
    rv_matrix_b_prefix_64(),
    rv_matrix_b_suffix_64(),
  )
  assert_matrix_case(
    "b-l19-nocheck",
    rv_matrix_b_frame_nocheck_l19(),
    rv_matrix_b_len(),
    rv_matrix_b_prefix_64(),
    rv_matrix_b_suffix_64(),
  )
  assert_matrix_case(
    "b-l19-long27",
    rv_matrix_b_frame_long27_l19(),
    rv_matrix_b_len(),
    rv_matrix_b_prefix_64(),
    rv_matrix_b_suffix_64(),
  )
}

///|
test "dictionary matrix payload C variants" {
  assert_matrix_case(
    "c-l1",
    rv_matrix_c_frame_l1(),
    rv_matrix_c_len(),
    rv_matrix_c_prefix_64(),
    rv_matrix_c_suffix_64(),
  )
  assert_matrix_case(
    "c-l9",
    rv_matrix_c_frame_l9(),
    rv_matrix_c_len(),
    rv_matrix_c_prefix_64(),
    rv_matrix_c_suffix_64(),
  )
  assert_matrix_case(
    "c-l19",
    rv_matrix_c_frame_l19(),
    rv_matrix_c_len(),
    rv_matrix_c_prefix_64(),
    rv_matrix_c_suffix_64(),
  )
  assert_matrix_case(
    "c-l19-nocheck",
    rv_matrix_c_frame_nocheck_l19(),
    rv_matrix_c_len(),
    rv_matrix_c_prefix_64(),
    rv_matrix_c_suffix_64(),
  )
  assert_matrix_case(
    "c-l19-long27",
    rv_matrix_c_frame_long27_l19(),
    rv_matrix_c_len(),
    rv_matrix_c_prefix_64(),
    rv_matrix_c_suffix_64(),
  )
}

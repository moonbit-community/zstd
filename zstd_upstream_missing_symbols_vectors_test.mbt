///|
test "upstream golden dictionary missing-symbols http default level" {
  assert_upstream_gdict_http_vector(
    "http-dict-missing-symbols-default",
    rv_up_gdict_missing_symbols_http_frame_default(),
  )
}

///|
test "upstream golden dictionary missing-symbols http default level no-check" {
  assert_upstream_gdict_http_vector(
    "http-dict-missing-symbols-default-nocheck",
    rv_up_gdict_missing_symbols_http_frame_default_nocheck(),
  )
}

///|
fn assert_missing_symbols_vector_requires_dictionary(
  frame : Bytes,
) -> Unit raise Error {
  let without_dict = try? decompress(frame)
  assert_true(without_dict is Err(DictionaryRequired(_)))

  let wrong_dict = standard_dictionary_fixture_dictionary()
  let with_wrong_dict = try? decompress_with_dictionary(frame, wrong_dict)
  assert_true(with_wrong_dict is Err(DictionaryRequired(_)))
}

///|
test "upstream missing-symbols vector rejects absent and wrong dictionary" {
  assert_missing_symbols_vector_requires_dictionary(
    rv_up_gdict_missing_symbols_http_frame_default(),
  )
}

///|
test "upstream missing-symbols no-check vector rejects absent and wrong dictionary" {
  assert_missing_symbols_vector_requires_dictionary(
    rv_up_gdict_missing_symbols_http_frame_default_nocheck(),
  )
}

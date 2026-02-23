///|
test "upstream missing-symbol dictionary encode byte parity default checksum" {
  let frame = compress_with_dictionary_and_options(
    rv_up_http_payload(),
    rv_up_gdict_http_dict(),
    default_compress_options(level=3).with_checksum(true),
  )
  assert_eq(frame, rv_up_gdict_missing_symbols_http_frame_default())
}

///|
test "upstream missing-symbol dictionary encode byte parity default no-check" {
  let frame = compress_with_dictionary_and_options(
    rv_up_http_payload(),
    rv_up_gdict_http_dict(),
    default_compress_options(level=3).with_checksum(false),
  )
  assert_eq(frame, rv_up_gdict_missing_symbols_http_frame_default_nocheck())
}

///|
test "upstream golden dictionary missing-symbols http default level" {
  assert_upstream_gdict_http_vector(
    "http-dict-missing-symbols-default",
    rv_up_gdict_missing_symbols_http_frame_default(),
  )
}

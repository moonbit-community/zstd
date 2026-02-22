///|
test "stream parity: dictionary-required error is surfaced from pull" {
  let dec = new_decompressor()
  dec.push(standard_dictionary_fixture_frame())
  let result = try? dec.pull()
  assert_true(result is Err(DictionaryRequired(_)))
  assert_true(dec.pending_input() > 0)
}

///|
test "stream parity: pull returns complete prefix frame with incomplete tail buffered" {
  let frame1 = compress(b"first")
  let frame2 = compress(b"second")
  let dec = new_decompressor()
  dec.push(frame1 + frame2[:frame2.length() - 2].to_bytes())
  let out = dec.pull()
  assert_eq(out, b"first")
  assert_true(dec.pending_input() > 0)
  let finish_result = try? dec.finish()
  assert_true(finish_result is Err(SrcSizeWrong))
}

///|
test "stream parity: dictionary decoder handles concatenated dictionary frames" {
  let frame = standard_dictionary_fixture_frame()
  let dict = standard_dictionary_fixture_dictionary()
  let dec = new_decompressor_with_dictionary(dict)
  dec.push(frame + frame)
  let out = dec.pull()
  assert_eq(
    out,
    standard_dictionary_fixture_payload() +
    standard_dictionary_fixture_payload(),
  )
  assert_eq(dec.pending_input(), 0)
}

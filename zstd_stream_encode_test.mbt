///|
test "stream compressor emits compressed frame from buffered chunks" {
  let enc = new_compressor()
  enc.push(b"hello ")
  enc.push(b"zstd")
  assert_eq(enc.pending_input(), 10)

  let compressed = enc.pull()
  assert_true(compressed.length() > 0)
  assert_eq(decompress(compressed), b"hello zstd")
  assert_eq(enc.pending_input(), 0)
  assert_eq(enc.pull(), b"")
}

///|
test "stream compressor supports multiple pulls as concatenated frames" {
  let enc = new_compressor()
  enc.push(b"abc")
  let frame1 = enc.pull()
  enc.push(b"xyz")
  let frame2 = enc.pull()
  assert_eq(decompress(frame1 + frame2), b"abcxyz")
}

///|
test "stream compressor finish flushes remaining input" {
  let enc = new_compressor(level=9)
  enc.push(b"tail")
  let frame = enc.finish()
  assert_eq(decompress(frame), b"tail")
  assert_eq(enc.pending_input(), 0)
  assert_eq(enc.finish(), b"")
}

///|
test "stream compressor with dictionary can roundtrip dictionary-referenced payload" {
  let dict = Bytes::makei(384, i => {
    ((i * 61 + 23) % 251).reinterpret_as_uint().to_byte()
  })
  let input = dict[140:236].to_bytes()
  let enc = new_compressor_with_dictionary(dict, level=12)
  enc.push(input)
  let frame = enc.finish()
  let no_dict = try? decompress(frame)
  assert_true(no_dict is Err(CorruptionDetected))
  assert_eq(decompress_with_dictionary(frame, dict), input)
}

///|
test "stream compressor with options can force raw block behavior" {
  let input = Bytes::makei(512, i => if i % 2 == 0 { b"a"[0] } else { b"b"[0] })
  let enc = new_compressor_with_options(
    default_compress_options(level=10).with_target_compressed_block_size(6),
  )
  enc.push(input)
  let frame = enc.finish()
  let header_size = frame_header_size_encode_test(frame)
  let block_header = read_u24_le_test(frame, header_size)
  assert_eq((block_header >> 1) & 0x3, 0)
  assert_eq(decompress(frame), input)
}

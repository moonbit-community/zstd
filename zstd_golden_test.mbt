///|
/// Upstream mapping:
/// - tests/golden-decompression/empty-block.zst
test "golden-decompression empty-block.zst" {
  let frame = b"\x28\xb5\x2f\xfd\x00\x00\x15\x00\x00\x00\x00"
  let parser_bound = decompress_bound(frame)
  assert_eq(parser_bound, (1024 : UInt64))
  let out = decompress(frame)
  assert_eq(out.length(), 0)
}

///|
/// Upstream mapping:
/// - tests/golden-decompression/rle-first-block.zst
test "golden-decompression rle-first-block.zst" {
  let frame = b"\x28\xb5\x2f\xfd\xa4\x00\x00\x10\x00\x02\x00\x10\x00\x02\x00\x10\x00\x02\x00\x10\x00\x02\x00\x10\x00\x02\x00\x10\x00\x02\x00\x10\x00\x02\x00\x10\x00\x03\x00\x10\x00\xf1\x3e\x16\xe1"
  let parser_bound = decompress_bound(frame)
  let out = decompress(frame)
  assert_eq(out.length().to_uint64(), parser_bound)
  assert_true(out.length().to_uint64() <= parser_bound)
}

///|
/// Upstream mapping:
/// - tests/golden-decompression/zeroSeq_2B.zst
test "golden-decompression zeroSeq_2B.zst" {
  let frame = b"\x28\xb5\x2f\xfd\x00\x00\x85\x00\x00\x68\x48\x65\x6c\x6c\x6f\x20\x57\x6f\x72\x6c\x64\x21\x0a\x80\x00"
  let out = decompress(frame)
  assert_eq(out, b"Hello World!\n")
}

///|
/// Upstream mapping:
/// - tests/golden-decompression-errors/zeroSeq_extraneous.zst
test "golden-decompression-errors zeroSeq_extraneous.zst" {
  let frame = b"\x28\xb5\x2f\xfd\x00\x00\x95\x00\x00\x68\x48\x65\x6c\x6c\x6f\x20\x57\x6f\x72\x6c\x64\x21\x0a\x80\x00\x00\x00"
  let result = try? decompress(frame)
  assert_true(result is Err(CorruptionDetected))
}

///|
/// Upstream mapping:
/// - tests/golden-decompression-errors/off0.bin.zst
test "golden-decompression-errors off0.bin.zst" {
  let frame = b"\x28\xb5\x2f\xfd\x00\x00\x45\x00\x00\x08\x00\x02\x00\x2f\x43\x0b\xae"
  let result = try? decompress(frame)
  assert_true(result is Err(_))
}

///|
test "golden-decompression-errors off0.bin.zst does not fail on unsupported sequence mode" {
  let frame = b"\x28\xb5\x2f\xfd\x00\x00\x45\x00\x00\x08\x00\x02\x00\x2f\x43\x0b\xae"
  let result = try? decompress(frame)
  assert_true(result is Err(CorruptionDetected) || result is Err(SrcSizeWrong))
}

///|
/// Upstream mapping:
/// - tests/golden-decompression-errors/truncated_huff_state.zst
test "golden-decompression-errors truncated_huff_state.zst" {
  let frame = b"\x28\xb5\x2f\xfd\x00\x00\x55\x00\x00\x72\x80\x01\x04\x20\x7e\x1f\x02\xaa\x00"
  let decomp_result = try? decompress(frame)
  assert_true(decomp_result is Err(_))
}

///|
fn build_block_128k_frame() -> Bytes {
  Bytes::makei(131081, i => {
    if i == 0 {
      b'\x28'
    } else if i == 1 {
      b'\xB5'
    } else if i == 2 {
      b'\x2F'
    } else if i == 3 {
      b'\xFD'
    } else if i == 5 {
      b'\x38'
    } else if i == 6 {
      b'\x05'
    } else if i == 8 {
      b'\x10'
    } else if i == 9 {
      b'\xCC'
    } else if i == 10 {
      b'\xFF'
    } else if i == 11 {
      b'\x1F'
    } else {
      b'\x00'
    }
  })
}

///|
test "golden-decompression block-128k.zst" {
  let frame = build_block_128k_frame()
  let out = decompress(frame)
  assert_eq(out.length(), 131068)
  assert_eq(out, Bytes::makei(131068, _ => b'\x00'))
}

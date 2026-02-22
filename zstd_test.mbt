///|
/// Ported from upstream:
/// - zstd/tests/fuzzer.c:test_compressBound()
test "compress_bound matches macro on power-of-two sizes" {
  let mut s = 0
  while s < 30 {
    let w = (1 : UInt64) << s
    assert_eq(compress_bound(w), compress_bound_macro(w))
    s = s + 1
  }
}

///|
/// Ported from upstream:
/// - zstd/tests/fuzzer.c:test_compressBound()
test "compress_bound raises on src size larger than max input" {
  let w : UInt64 = 0xFF00FF00FF00FF00 + 1
  let result = try? compress_bound(w)
  match result {
    Err(SrcSizeTooLarge(size)) => assert_eq(size, w)
    _ => fail("expected SrcSizeTooLarge")
  }
  assert_eq(compress_bound_macro(w), 0)
}

///|
/// Ported from upstream:
/// - zstd/tests/fuzzer.c:test_decompressBound()
test "decompress_bound returns frame content size for single-segment frame" {
  let frame = b"\x28\xB5\x2F\xFD\x20\x04\x21\x00\x00\x61\x62\x63\x64"
  assert_eq(decompress_bound(frame), (4 : UInt64))
}

///|
/// Ported from upstream:
/// - zstd/tests/fuzzer.c:test_decompressBound()
test "decompress_bound returns one block max when content size is missing" {
  let frame = b"\x28\xB5\x2F\xFD\x00\x38\x01\x00\x00"
  assert_eq(decompress_bound(frame), (128 : UInt64) << 10)
}

///|
/// Ported from upstream:
/// - zstd/tests/fuzzer.c:test_decompressBound()
test "decompress_bound sums concatenated frame bounds" {
  let frame1 = b"\x28\xB5\x2F\xFD\x20\x04\x21\x00\x00\x61\x62\x63\x64"
  let frame2 = b"\x28\xB5\x2F\xFD\x20\x03\x19\x00\x00\x78\x79\x7A"
  assert_eq(decompress_bound(frame1 + frame2), (7 : UInt64))
}

///|
/// Ported from upstream:
/// - zstd/tests/fuzzer.c:test_decompressBound()
test "decompress_bound ignores skippable frame payload in bound" {
  let skippable = b"\x50\x2A\x4D\x18\x04\x00\x00\x00test"
  let frame = b"\x28\xB5\x2F\xFD\x20\x04\x21\x00\x00\x61\x62\x63\x64"
  assert_eq(decompress_bound(skippable + frame), (4 : UInt64))
}

///|
/// Ported from upstream:
/// - zstd/tests/fuzzer.c:test_decompressBound()
test "decompress_bound raises when frame payload is truncated" {
  let frame = b"\x28\xB5\x2F\xFD\x20\x04\x21\x00\x00\x61\x62\x63\x64"
  let truncated = frame[:frame.length() - 1].to_bytes()
  let result = try? decompress_bound(truncated)
  assert_true(result is Err(SrcSizeWrong))
}

///|
test "pure compress/decompress roundtrip with raw blocks" {
  let input = b"moonbit pure zstd"
  let compressed = compress(input)
  let restored = decompress(compressed)
  assert_eq(restored, input)
}

///|
test "pure compress handles payload larger than one zstd block" {
  let input = Bytes::makei(140000, i => (i % 251).to_byte())
  let compressed = compress(input)
  let restored = decompress(compressed)
  assert_eq(restored, input)
}

///|
test "decode compressed block subset: one sequence" {
  // Frame:
  // - single segment, content size 4
  // - one compressed block (size 7)
  // - literals: raw 'a'
  // - sequence section: 1 sequence, all RLE modes, LL=1, Off=0, ML=0
  let frame = b"\x28\xb5\x2f\xfd\x20\x04\x3d\x00\x00\x08\x61\x01\x54\x01\x00\x00"
  let out = decompress(frame)
  assert_eq(out, b"aaaa")
}

///|
test "decode compressed block subset: two sequences" {
  // Same subset encoding, but Number_of_Sequences=2 and literals are 'a','b'.
  let frame = b"\x28\xb5\x2f\xfd\x20\x08\x45\x00\x00\x10\x61\x62\x02\x54\x01\x00\x00"
  let out = decompress(frame)
  assert_eq(out, b"aaaabbbb")
}

///|
test "compressed block subset rejects unsupported sequence bitstream" {
  // LL mode is FSE compressed (mode=2) but section is intentionally malformed.
  let frame = b"\x28\xb5\x2f\xfd\x20\x04\x3d\x00\x00\x08\x61\x01\x94\x00\x00\x00"
  let result = try? decompress(frame)
  assert_true(result is Err(CorruptionDetected))
}

///|
test "decode compressed block subset with reverse bitstream extras" {
  // One sequence, off_code=2 with 2 extra bits set to 0 (bitstream byte 0x04),
  // so offset_value=4 -> offset=1.
  let frame = b"\x28\xb5\x2f\xfd\x20\x04\x45\x00\x00\x08\x61\x01\x54\x01\x02\x00\x04"
  let out = decompress(frame)
  assert_eq(out, b"aaaa")
}

///|
test "compressed block subset detects insufficient reverse bits" {
  // Same frame as above but with bitstream byte 0x01 (no available payload bits).
  let frame = b"\x28\xb5\x2f\xfd\x20\x04\x45\x00\x00\x08\x61\x01\x54\x01\x02\x00\x01"
  let result = try? decompress(frame)
  assert_true(result is Err(CorruptionDetected))
}

///|
test "decode compressed block subset with repeat sequence mode" {
  // Two compressed blocks:
  // 1) all-RLE sequence modes (establishes previous sequence tables)
  // 2) all-Repeat sequence modes (reuses previous RLE symbols)
  let frame = b"\x28\xb5\x2f\xfd\x20\x08\x3c\x00\x00\x08\x61\x01\x54\x01\x00\x00\x25\x00\x00\x08\x62\x01\xfc"
  let out = decompress(frame)
  assert_eq(out, b"aaaabbbb")
}

///|
test "repeat sequence mode without previous table is rejected" {
  let frame = b"\x28\xb5\x2f\xfd\x20\x04\x25\x00\x00\x08\x61\x01\xfc"
  let result = try? decompress(frame)
  assert_true(result is Err(CorruptionDetected))
}

///|
test "decode compressed block subset with predefined sequence mode" {
  // One sequence with all predefined modes.
  // Sequence bitstream initializes LL state=2 (base=1), OF state=0 (repcode), ML state=0 (base=3).
  let frame = b"\x28\xb5\x2f\xfd\x20\x04\x3d\x00\x00\x08\x61\x01\x00\x00\x10\x02"
  let out = decompress(frame)
  assert_eq(out, b"aaaa")
}

///|
test "repeat sequence mode can reuse predefined sequence tables" {
  // Block1 uses predefined sequence tables; block2 repeats them.
  let frame = b"\x28\xb5\x2f\xfd\x20\x08\x3c\x00\x00\x08\x61\x01\x00\x00\x10\x02\x3d\x00\x00\x08\x62\x01\xfc\x00\x10\x02"
  let out = decompress(frame)
  assert_eq(out, b"aaaabbbb")
}

///|
test "decompress_with_dictionary supports initial history matches" {
  // One sequence: LL=0, ML=3, offset code=4 + extra=3 => offset=16.
  // Output is matched entirely from dictionary history.
  let frame = b"\x28\xb5\x2f\xfd\x20\x03\x3d\x00\x00\x00\x01\x54\x00\x04\x00\x13"
  let dict = b"0123456789abcdef"
  let result_without = try? decompress(frame)
  assert_true(result_without is Err(CorruptionDetected))
  let out = decompress_with_dictionary(frame, dict)
  assert_eq(out, b"012")
}

///|
test "frame with dictionary id requires dictionary in this subset" {
  let frame = b"\x28\xb5\x2f\xfd\x21\x01\x03\x3d\x00\x00\x00\x01\x54\x00\x04\x00\x13"
  let dict = b"0123456789abcdef"
  let result = try? decompress(frame)
  assert_true(result is Err(DictionaryRequired(_)))
  let out = decompress_with_dictionary(frame, dict)
  assert_eq(out, b"012")
}

///|
test "decompress_with_dictionary supports standard zstd dictionary blob" {
  let frame = standard_dictionary_fixture_frame()
  let dict = standard_dictionary_fixture_dictionary()
  let expected = standard_dictionary_fixture_payload()
  let result_without = try? decompress(frame)
  assert_true(result_without is Err(DictionaryRequired(_)))
  let out = decompress_with_dictionary(frame, dict)
  assert_eq(out, expected)
}

///|
test "standard dictionary dictID mismatch is rejected" {
  let frame = standard_dictionary_fixture_frame()
  let dict = standard_dictionary_fixture_dictionary()
  let bad_dict = Bytes::makei(dict.length(), i => {
    if i == 4 {
      (dict[i].to_uint() ^ 1).to_byte()
    } else {
      dict[i]
    }
  })
  let result = try? decompress_with_dictionary(frame, bad_dict)
  assert_true(result is Err(CorruptionDetected))
}

///|
test "decompress validates frame checksum when present" {
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\x01\x02\x00\x44\x20\x82\x3c\xfd\xe6\xf1\xc2\x6b\x30\xf9\x0e\xc7\xdd\x01\xe4\x88\x75\x34\xa2\x0f\x0b\x0d\x04\xc3\x6e\xd8\x0e\x71\xe0\xfd\x77\xb0\x76\x70\xeb\x94\x0b\xd5\x33\x5f\x97\x3d\xaa\xd8\x61\x9b\x91\xff\xc9\x11\xf5\x7c\xce\xd4\x58\xbb\xbf\x2c\xe0\x37\x53\xc9\xbd\xad\x85\xec\x3d"
  let expected = b"\x44\x20\x82\x3c\xfd\xe6\xf1\xc2\x6b\x30\xf9\x0e\xc7\xdd\x01\xe4\x88\x75\x34\xa2\x0f\x0b\x0d\x04\xc3\x6e\xd8\x0e\x71\xe0\xfd\x77\xb0\x76\x70\xeb\x94\x0b\xd5\x33\x5f\x97\x3d\xaa\xd8\x61\x9b\x91\xff\xc9\x11\xf5\x7c\xce\xd4\x58\xbb\xbf\x2c\xe0\x37\x53\xc9\xbd"
  let out = decompress(frame)
  assert_eq(out, expected)
}

///|
test "decompress rejects corrupted frame checksum" {
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\x01\x02\x00\x44\x20\x82\x3c\xfd\xe6\xf1\xc2\x6b\x30\xf9\x0e\xc7\xdd\x01\xe4\x88\x75\x34\xa2\x0f\x0b\x0d\x04\xc3\x6e\xd8\x0e\x71\xe0\xfd\x77\xb0\x76\x70\xeb\x94\x0b\xd5\x33\x5f\x97\x3d\xaa\xd8\x61\x9b\x91\xff\xc9\x11\xf5\x7c\xce\xd4\x58\xbb\xbf\x2c\xe0\x37\x53\xc9\xbd\xad\x85\xec\x3d"
  let bad_last = (frame[frame.length() - 1].to_uint() ^ 1).to_byte()
  let bad_frame = frame[:frame.length() - 1].to_bytes() +
    Bytes::makei(1, _ => bad_last)
  let result = try? decompress(bad_frame)
  assert_true(result is Err(CorruptionDetected))
}

///|
test "decode compressed literals block with direct Huffman weights (single stream)" {
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\xc5\x00\x00\x02\x04\x05\x82\x11\x10\x3d\x34\xf8\xdb\x1b\x6d\x3a\x68\xe4\xed\xe7\x48\xbd\x3c\x27\x9a\x01\x00\xe3\x43\x89\xf5"
  let out = decompress(frame)
  let expected = b"\x02\x01\x02\x02\x00\x02\x01\x03\x00\x03\x03\x00\x02\x03\x03\x01\x01\x00\x02\x00\x03\x02\x01\x03\x03\x02\x03\x01\x03\x02\x01\x00\x01\x02\x02\x00\x00\x03\x02\x02\x01\x02\x03\x01\x00\x01\x02\x03\x03\x01\x02\x03\x03\x03\x02\x00\x00\x03\x01\x00\x00\x03\x03\x01"
  assert_eq(out, expected)
}

///|
test "decode compressed literals block with FSE-compressed Huffman weights" {
  // Generated by zstd CLI v1.5.5 (`zstd -19`) on a 64-byte nibble-valued payload.
  // This frame uses literals block type=2 where the Huffman tree description header byte is < 128.
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\x55\x01\x00\x02\x84\x09\x05\x30\xfa\x36\x64\x0b\x57\x73\x78\x62\x90\x58\x55\xcd\x78\x86\xdc\xa9\xfd\xe8\x84\x40\x94\xe7\xdd\x3a\xc3\x8c\x64\x99\xf9\xbb\xfa\xb9\x4e\xb9\xcc\x01\x00\x6b\x71\xa5\xdd"
  let expected = b"\x0e\x0e\x0d\x0b\x05\x01\x06\x0e\x01\x01\x06\x08\x08\x01\x0b\x0b\x0b\x07\x05\x0a\x0e\x0e\x04\x04\x0c\x0f\x0f\x01\x04\x0e\x0c\x03\x00\x05\x03\x08\x05\x08\x01\x07\x0c\x08\x08\x03\x02\x0b\x01\x02\x0b\x0c\x0c\x0c\x0d\x02\x03\x00\x0e\x05\x01\x0a\x08\x04\x06\x08"
  let out = decompress(frame)
  assert_eq(out, expected)
}

///|
test "treeless literals block without previous Huffman tree is rejected" {
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\xc5\x00\x00\x03\x04\x05\x82\x11\x10\x3d\x34\xf8\xdb\x1b\x6d\x3a\x68\xe4\xed\xe7\x48\xbd\x3c\x27\x9a\x01\x00\xe3\x43\x89\xf5"
  let result = try? decompress(frame)
  assert_true(result is Err(CorruptionDetected))
}

///|
test "decompress_with_dictionary handles real dictionary-compressed frame (zstd cli)" {
  let dict = b"\x37\xa4\x30\xec\xdb\xc3\xd0\x3f\x2d\x10\x90\x1d\x3a\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x40\x31\xdb\x14\xb3\x4d\x31\xdb\x14\x1b\xb7\x94\x52\xca\x24\xf5\x15\xa5\x5e" +
    b"\x51\xea\x15\xa5\xde\xfb\xa3\x04\x00\x00\x00\x2b\xd4\x9c\x00\x00\x00\x34\x60\xc0\x80\x1e\x44\x12\x06\x06\x06\x06\x7a\x06\x08\x06\x98\x06\x83\xc1\x60\x30\x18\x0c\x06\x83\xc1\xcf\x60\x30\x18\x0c" +
    b"\x06\xc8\x31\x26\x32\xc6\xcc\xcc\xcc\xcc\xb6\x0d\x44\xf3\xca\x36\x0c\xc3\x30\xc6\x18\x63\x8c\x31\xc6\x18\x63\x8c\x31\x33\x33\x33\xb3\x6d\x03\x01\x00\x00\x00\x04\x00\x00\x00\x08\x00\x00\x00\x6b" +
    b"\x65\x6e\x2d\x34\x36\x20\x72\x65\x70\x65\x61\x74\x65\x64\x20\x61\x6c\x70\x68\x61\x20\x62\x65\x74\x61\x20\x67\x61\x6d\x6d\x61\x20\x73\x65\x63\x74\x69\x6f\x6e\x2d\x30\x31\x20\x61\x6e\x64\x20\x65" +
    b"\x78\x6b\x65\x6e\x2d\x33\x39\x20\x72\x65\x70\x65\x61\x74\x65\x64\x20\x61\x6c\x70\x68\x61\x20\x62\x65\x74\x61\x20\x67\x61\x6d\x6d\x61\x20\x73\x65\x63\x74\x69\x6f\x6e\x2d\x30\x33\x20\x61\x6e\x64" +
    b"\x20\x65\x78\x74\x69\x6f\x6e\x61\x72\x79\x20\x73\x74\x61\x62\x69"
  let frame = b"\x28\xb5\x2f\xfd\x27\xdb\xc3\xd0\x3f\x5c\x0d\x02\x00\xf4\x02\x63\x6f\x6d\x70\x72\x65\x73\x73\x20\x77\x69\x74\x68\x20\x64\x69\x63\x61\x6d\x70\x6c\x65\x20\x70\x61\x79\x6c\x6f\x61\x74\x6f\x6b\x65" +
    b"\x6e\x2d\x30\x35\x35\x72\x61\x20\x77\x6f\x72\x64\x73\x0a\x04\xfc\x62\x8f\x80\xca\x2a\x9b\x8c\x5e\x67\x87\xf3\xc1\xcb\x02\x14\x32\x07\xf9"
  let expected = b"\x63\x6f\x6d\x70\x72\x65\x73\x73\x20\x77\x69\x74\x68\x20\x64\x69\x63\x74\x69\x6f\x6e\x61\x72\x79\x20\x73\x61\x6d\x70\x6c\x65\x20\x70\x61\x79\x6c\x6f\x61\x64\x20\x61\x6c\x70\x68\x61\x20\x62\x65" +
    b"\x74\x61\x20\x67\x61\x6d\x6d\x61\x20\x74\x6f\x6b\x65\x6e\x2d\x30\x35\x20\x73\x65\x63\x74\x69\x6f\x6e\x2d\x35\x20\x61\x6e\x64\x20\x65\x78\x74\x72\x61\x20\x77\x6f\x72\x64\x73\x0a"
  let frame_no_checksum = {
    let arr = frame[:frame.length() - 4].to_array()
    arr[4] = (arr[4].to_uint() & 0xFB).to_byte()
    Bytes::from_array(arr)
  }
  let no_checksum_result = try? decompress_with_dictionary(
    frame_no_checksum, dict,
  )
  match no_checksum_result {
    Ok(out) => assert_eq(out, expected)
    Err(SrcSizeTooLarge(_)) => fail("no-checksum: SrcSizeTooLarge")
    Err(SrcSizeWrong) => fail("no-checksum: SrcSizeWrong")
    Err(CorruptionDetected) => fail("no-checksum: CorruptionDetected")
    Err(BoundOverflow) => fail("no-checksum: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail("no-checksum: DictionaryRequired " + dict_id.to_string())
    Err(UnsupportedFeature(msg)) =>
      fail("no-checksum: UnsupportedFeature " + msg)
  }
  let with_checksum_result = try? decompress_with_dictionary(frame, dict)
  match with_checksum_result {
    Ok(out) => assert_eq(out, expected)
    Err(_) => fail("checksum path failed")
  }
}

///|
fn assert_real_vector_p01(frame : Bytes) -> Unit raise Error {
  let result = try? decompress_with_dictionary(frame, rv_dict_20260222())
  match result {
    Ok(out) => {
      assert_eq(out.length(), 3624)
      assert_eq(out[:64].to_bytes(), rv_p01_prefix_64())
      assert_eq(out[out.length() - 64:].to_bytes(), rv_p01_suffix_64())
    }
    Err(SrcSizeTooLarge(_)) =>
      fail("real vector p01 decode failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) => fail("real vector p01 decode failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail("real vector p01 decode failed: CorruptionDetected")
    Err(BoundOverflow) => fail("real vector p01 decode failed: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "real vector p01 decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail("real vector p01 decode failed: UnsupportedFeature " + msg)
  }
}

///|
test "real dictionary vector p01 level1" {
  assert_real_vector_p01(rv_frame_p01_l1())
}

///|
test "real dictionary vector p01 level9" {
  assert_real_vector_p01(rv_frame_p01_l9())
}

///|
test "real dictionary vector p01 level19" {
  assert_real_vector_p01(rv_frame_p01_l19())
}

///|
test "real dictionary vector p01 level19 without checksum field" {
  let frame = rv_frame_p01_l19()
  let arr = frame[:frame.length() - 4].to_array()
  arr[4] = (arr[4].to_uint() & 0xFB).to_byte()
  let no_checksum_frame = Bytes::from_array(arr)
  assert_real_vector_p01(no_checksum_frame)
}

///|
test "real dictionary vector p01 with checksum" {
  assert_real_vector_p01(rv_frame_p01_chk())
}

///|
test "real dictionary vector p01 without checksum" {
  assert_real_vector_p01(rv_frame_p01_nochk())
}

///|
test "real dictionary vector p01 long27" {
  assert_real_vector_p01(rv_frame_p01_long27())
}

///|
fn assert_real_cli_vector_p02(frame : Bytes) -> Unit raise Error {
  let expected = rv_cli_p02_payload()
  let result = try? decompress(frame)
  match result {
    Ok(out) => assert_eq(out, expected)
    Err(SrcSizeTooLarge(_)) =>
      fail("real CLI p02 decode failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) => fail("real CLI p02 decode failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail("real CLI p02 decode failed: CorruptionDetected")
    Err(BoundOverflow) => fail("real CLI p02 decode failed: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "real CLI p02 decode failed: DictionaryRequired " + dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail("real CLI p02 decode failed: UnsupportedFeature " + msg)
  }
}

///|
test "real cli vector p02 level1" {
  assert_real_cli_vector_p02(rv_cli_p02_frame_l1())
}

///|
test "real cli vector p02 level19" {
  assert_real_cli_vector_p02(rv_cli_p02_frame_l19())
}

///|
test "real cli vector p02 long27" {
  assert_real_cli_vector_p02(rv_cli_p02_frame_long27())
}

///|
test "real cli vector p02 no-check level9" {
  assert_real_cli_vector_p02(rv_cli_p02_frame_nocheck_l9())
}

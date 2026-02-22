///|
fn read_u24_le_test(src : Bytes, pos : Int) -> UInt {
  src[pos].to_uint() +
  (src[pos + 1].to_uint() << 8) +
  (src[pos + 2].to_uint() << 16)
}

///|
fn append_bytes_encode_test(
  out : Array[Byte],
  src : Bytes,
  start : Int,
  len : Int,
) -> Unit {
  let mut i = 0
  while i < len {
    out.push(src[start + i])
    i = i + 1
  }
}

///|
test "compress emits rle block for repeated payload" {
  let input = b"aaaaaaaaaaaaaaaa"
  let frame = compress(input)
  assert_eq(decompress(frame), input)

  let block_header = read_u24_le_test(frame, 9)
  assert_eq(block_header & 1, 1) // last block
  assert_eq((block_header >> 1) & 0x3, 1) // rle block
  assert_eq((block_header >> 3).reinterpret_as_int(), input.length())
  assert_eq(frame[12], b"a"[0])
}

///|
test "compress emits raw block for mixed payload" {
  let input = b"abababab"
  let frame = compress(input)
  assert_eq(decompress(frame), input)

  let block_header = read_u24_le_test(frame, 9)
  assert_eq((block_header >> 1) & 0x3, 0)
  assert_eq((block_header >> 3).reinterpret_as_int(), input.length())
}

///|
test "compress emits rle blocks across 128k boundary" {
  let input = Bytes::makei((128 << 10) + 97, _ => b"x"[0])
  let frame = compress(input)
  assert_eq(decompress(frame), input)

  let block1_header = read_u24_le_test(frame, 9)
  assert_eq(block1_header & 1, 0)
  assert_eq((block1_header >> 1) & 0x3, 1)
  assert_eq((block1_header >> 3).reinterpret_as_int(), 128 << 10)

  let block2_pos = 9 + 3 + 1
  let block2_header = read_u24_le_test(frame, block2_pos)
  assert_eq(block2_header & 1, 1)
  assert_eq((block2_header >> 1) & 0x3, 1)
  assert_eq((block2_header >> 3).reinterpret_as_int(), 97)
}

///|
test "compress emits compressed block for periodic payload at higher level" {
  let input = Bytes::makei(512, i => if i % 2 == 0 { b"a"[0] } else { b"b"[0] })

  let frame_low = compress(input, level=3)
  let block_low = read_u24_le_test(frame_low, 9)
  assert_eq((block_low >> 1) & 0x3, 0)

  let frame_high = compress(input, level=10)
  let block_high = read_u24_le_test(frame_high, 9)
  assert_eq((block_high >> 1) & 0x3, 2)
  assert_true(frame_high.length() < frame_low.length())
  assert_eq(decompress(frame_high), input)
}

///|
test "compress periodic payload with larger period uses higher offset code" {
  let unit = b"abcdefghijklmn"[:13].to_bytes()
  let input_arr : Array[Byte] = Array::new()
  let mut i = 0
  while i < 64 {
    let mut j = 0
    while j < unit.length() {
      input_arr.push(unit[j])
      j = j + 1
    }
    i = i + 1
  }
  let input = Bytes::from_array(input_arr)

  let frame = compress(input, level=10)
  let block_header = read_u24_le_test(frame, 9)
  assert_eq((block_header >> 1) & 0x3, 2)
  assert_eq(decompress(frame), input)

  // payload starts at frame offset 12:
  // [raw literals header(1)] [13 literals] [seq_count(1)] [modes(1)] [ll_code(1)] [off_code(1)]
  let off_code_pos = 12 + 1 + 13 + 1 + 1 + 1
  assert_eq(frame[off_code_pos].to_uint(), 4)
}

///|
test "compress periodic prefix with literal tail emits compressed block" {
  let head = Bytes::makei(480, i => {
    if i % 3 == 0 {
      b"a"[0]
    } else if i % 3 == 1 {
      b"b"[0]
    } else {
      b"c"[0]
    }
  })
  let tail = b"tail-unique-42"
  let input = head + tail

  let frame_low = compress(input, level=3)
  let frame_high = compress(input, level=10)
  let block_high = read_u24_le_test(frame_high, 9)
  assert_eq((block_high >> 1) & 0x3, 2)
  assert_true(frame_high.length() < frame_low.length())
  assert_eq(decompress(frame_high), input)
}

///|
test "compress can use periodic window after literal prefix" {
  let prefix = b"HEADER:"
  let window = Bytes::makei(360, i => if i % 2 == 0 { b"a"[0] } else { b"b"[0] })
  let tail = b":END"
  let input = prefix + window + tail

  let frame_low = compress(input, level=3)
  let frame_high = compress(input, level=10)
  let block_high = read_u24_le_test(frame_high, 9)
  assert_eq((block_high >> 1) & 0x3, 2)
  assert_true(frame_high.length() < frame_low.length())
  assert_eq(decompress(frame_high), input)

  // For this shape encoder falls back to single sequence due prefixed literals.
  // literals = prefix(7) + period(2) + tail(4) => 13 bytes, raw literals header is 1 byte.
  let seq_count_pos = 12 + 1 + 13
  assert_eq(frame_high[seq_count_pos].to_uint(), 1)
}

///|
test "compress prefix periodic window can use multi-sequence when LL range fits" {
  let prefix = b"X"
  let period = b"abcdefghijklmnop" // 16 bytes
  let body_arr : Array[Byte] = Array::new()
  let mut i = 0
  while i < 20 {
    append_bytes_encode_test(body_arr, period, 0, period.length())
    i = i + 1
  }
  let body = Bytes::from_array(body_arr)
  let input = prefix + body + b"Z"

  let frame = compress(input, level=18)
  let block_header = read_u24_le_test(frame, 9)
  assert_eq((block_header >> 1) & 0x3, 2)
  assert_eq(decompress(frame), input)

  // literals = prefix(1) + period(16) + period(16) + tail(1) = 34 bytes.
  // raw literals header uses size_format=1 => 2-byte header.
  let seq_count_pos = 12 + 2 + 34
  assert_eq(frame[seq_count_pos].to_uint(), 2)
}

///|
test "compress can encode non-periodic repeated segment as single match" {
  let phrase = b"the quick brown fox jumps over the lazy dog|"
  let input = b"prefix@" + phrase + b"--" + phrase + b"@tail"

  let frame_low = compress(input, level=3)
  let frame_high = compress(input, level=12)
  let block_high = read_u24_le_test(frame_high, 9)
  assert_eq((block_high >> 1) & 0x3, 2)
  assert_true(frame_high.length() < frame_low.length())
  assert_eq(decompress(frame_high), input)
}

///|
test "compress very high level can emit two-sequence periodic block" {
  let head = Bytes::makei(200, i => if i % 2 == 0 { b"a"[0] } else { b"b"[0] })
  let tail = b"XYZ"
  let input = head + tail

  let frame = compress(input, level=18)
  let block_header = read_u24_le_test(frame, 9)
  assert_eq((block_header >> 1) & 0x3, 2)
  assert_eq(decompress(frame), input)

  // literals length = 2(seq1) + 2(seq2) + 3(tail) = 7, so raw literals header is 1 byte.
  let seq_count_pos = 12 + 1 + 7
  assert_eq(frame[seq_count_pos].to_uint(), 2)
}

///|
test "compress ultra level can emit four-sequence periodic block" {
  let head = Bytes::makei(240, i => if i % 2 == 0 { b"a"[0] } else { b"b"[0] })
  let tail = b"Q"
  let input = head + tail

  let frame = compress(input, level=24)
  let block_header = read_u24_le_test(frame, 9)
  assert_eq((block_header >> 1) & 0x3, 2)
  assert_eq(decompress(frame), input)

  // literals length = 2 * 4 + 1 = 9, raw literals header size is 1 byte.
  let seq_count_pos = 12 + 1 + 9
  assert_eq(frame[seq_count_pos].to_uint(), 4)
}

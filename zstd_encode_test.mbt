///|
fn read_u24_le_test(src : Bytes, pos : Int) -> UInt {
  src[pos].to_uint() +
  (src[pos + 1].to_uint() << 8) +
  (src[pos + 2].to_uint() << 16)
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

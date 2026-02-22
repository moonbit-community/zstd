///|
fn read_u24_le_test(src : Bytes, pos : Int) -> UInt {
  src[pos].to_uint() +
  (src[pos + 1].to_uint() << 8) +
  (src[pos + 2].to_uint() << 16)
}

///|
fn read_u32_le_test(src : Bytes, pos : Int) -> UInt {
  src[pos].to_uint() +
  (src[pos + 1].to_uint() << 8) +
  (src[pos + 2].to_uint() << 16) +
  (src[pos + 3].to_uint() << 24)
}

///|
fn dict_id_size_encode_test(flag : UInt) -> Int {
  if flag == 0 {
    0
  } else if flag == 1 {
    1
  } else if flag == 2 {
    2
  } else {
    4
  }
}

///|
fn frame_content_size_size_encode_test(
  flag : UInt,
  single_segment : Bool,
) -> Int {
  if flag == 0 {
    if single_segment {
      1
    } else {
      0
    }
  } else if flag == 1 {
    2
  } else if flag == 2 {
    4
  } else {
    8
  }
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
fn read_sequence_meta_from_compressed_payload(
  frame : Bytes,
  payload_start : Int,
  payload_end : Int,
) -> (Int, Int) {
  if payload_start < 0 ||
    payload_end > frame.length() ||
    payload_start >= payload_end {
    return (-1, -1)
  }
  let lit_desc = frame[payload_start].to_uint()
  if (lit_desc & 0x3) != 0 {
    return (-1, -1)
  }
  let size_format = (lit_desc >> 2) & 0x3
  let (lit_header_size, lit_len) = if size_format == 0 {
    (1, (lit_desc >> 3).reinterpret_as_int())
  } else if size_format == 1 {
    if payload_start + 1 >= frame.length() {
      return (-1, -1)
    }
    let lit = ((lit_desc >> 4) + (frame[payload_start + 1].to_uint() << 4)).reinterpret_as_int()
    (2, lit)
  } else if size_format == 3 {
    if payload_start + 2 >= frame.length() {
      return (-1, -1)
    }
    let lit = ((lit_desc >> 4) +
    (frame[payload_start + 1].to_uint() << 4) +
    (frame[payload_start + 2].to_uint() << 12)).reinterpret_as_int()
    (3, lit)
  } else {
    return (-1, -1)
  }
  let seq_count_pos = payload_start + lit_header_size + lit_len
  if seq_count_pos >= payload_end {
    return (-1, -1)
  }
  let seq0 = frame[seq_count_pos].to_uint()
  let seq_count_header_len = if seq0 < 128 {
    1
  } else if seq0 < 255 {
    2
  } else {
    3
  }
  let modes_pos = seq_count_pos + seq_count_header_len
  if modes_pos >= payload_end {
    return (-1, -1)
  }
  (seq0.reinterpret_as_int(), frame[modes_pos].to_uint().reinterpret_as_int())
}

///|
fn read_first_block_sequence_meta(frame : Bytes) -> (Int, Int) {
  if frame.length() < 13 {
    return (-1, -1)
  }
  let block_header = read_u24_le_test(frame, 9)
  if ((block_header >> 1) & 0x3) != 2 {
    return (-1, -1)
  }
  let block_size = (block_header >> 3).reinterpret_as_int()
  let payload_start = 12
  let payload_end = payload_start + block_size
  read_sequence_meta_from_compressed_payload(frame, payload_start, payload_end)
}

///|
fn read_first_block_sequence_modes(frame : Bytes) -> Int {
  let (_, modes) = read_first_block_sequence_meta(frame)
  modes
}

///|
fn read_first_block_sequence_count(frame : Bytes) -> Int {
  let (seq_count, _) = read_first_block_sequence_meta(frame)
  seq_count
}

///|
fn frame_header_size_encode_test(frame : Bytes) -> Int {
  if frame.length() < 5 {
    return -1
  }
  let descriptor = frame[4].to_uint()
  let single_segment = ((descriptor >> 5) & 1) == 1
  let mut size = 5
  if !single_segment {
    size = size + 1
  }
  let dict_flag = descriptor & 0x3
  size = size + dict_id_size_encode_test(dict_flag)
  let fcs_flag = descriptor >> 6
  size = size + frame_content_size_size_encode_test(fcs_flag, single_segment)
  size
}

///|
fn first_block_type_encode_test(frame : Bytes) -> Int {
  let header_size = frame_header_size_encode_test(frame)
  if header_size < 0 || header_size + 3 > frame.length() {
    return -1
  }
  let block_header = read_u24_le_test(frame, header_size)
  ((block_header >> 1) & 0x3).reinterpret_as_int()
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
test "compress can emit frame checksum when requested" {
  let input = b"checksum-enabled-payload"
  let frame = compress(input, checksum=true)
  // Descriptor bit2 is checksum flag.
  assert_eq(frame[4].to_uint() & 0x4, 0x4)
  assert_eq(decompress(frame), input)
}

///|
test "compress default keeps checksum disabled" {
  let frame = compress(b"no-checksum-default")
  assert_eq(frame[4].to_uint() & 0x4, 0)
}

///|
test "compress_with_dictionary emits dictID for standard dictionary" {
  let dict = standard_dictionary_fixture_dictionary()
  let input = standard_dictionary_fixture_payload()
  let frame = compress_with_dictionary(input, dict, level=12)
  assert_eq(frame[4].to_uint() & 0x3, 3)
  assert_eq(read_u32_le_test(frame, 5), read_u32_le_test(dict, 4))
  let without_dict = try? decompress(frame)
  assert_true(without_dict is Err(DictionaryRequired(_)))
  assert_eq(decompress_with_dictionary(frame, dict), input)
}

///|
test "compress_with_dictionary keeps dictID absent for raw dictionary history" {
  let dict = b"raw-prefix-history-dictionary"
  let input = b"plain payload"
  let frame = compress_with_dictionary(input, dict, level=12)
  assert_eq(frame[4].to_uint() & 0x3, 0)
  assert_eq(decompress(frame), input)
}

///|
test "compress_with_dictionary can use first-block dictionary single match" {
  let dict = Bytes::makei(512, i => {
    ((i * 73 + 19) % 251).reinterpret_as_uint().to_byte()
  })
  let input = dict[200:290].to_bytes()

  let frame_without = compress(input, level=12)
  let frame_with = compress_with_dictionary(input, dict, level=12)
  assert_eq(first_block_type_encode_test(frame_without), 0)
  assert_eq(first_block_type_encode_test(frame_with), 2)
  assert_true(frame_with.length() < frame_without.length())
  let decode_without = try? decompress(frame_with)
  assert_true(decode_without is Err(CorruptionDetected))
  assert_eq(decompress_with_dictionary(frame_with, dict), input)
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
test "compress single-match path can emit predefined sequence modes" {
  let prefix = Bytes::makei(61, i => {
    ((i * 17 + 13) % 251).reinterpret_as_uint().to_byte()
  })
  let repeated = Bytes::makei(73, i => {
    ((i * 19 + 7) % 239).reinterpret_as_uint().to_byte()
  })
  let input = prefix + repeated + b"||" + repeated + b"@"

  let frame = compress(input, level=12)
  let block_header = read_u24_le_test(frame, 9)
  assert_eq((block_header >> 1) & 0x3, 2)
  assert_eq(decompress(frame), input)

  let modes = read_first_block_sequence_modes(frame)
  assert_eq(modes, 0)
}

///|
test "compress ultra level can prefer mode2 compressed sequence payload" {
  let prefix = Bytes::makei(80, i => {
    ((i * 11 + 29) % 251).reinterpret_as_uint().to_byte()
  })
  let a = Bytes::makei(180, i => {
    ((i * 13 + 7) % 241).reinterpret_as_uint().to_byte()
  })
  let b = Bytes::makei(220, i => {
    ((i * 17 + 101) % 239).reinterpret_as_uint().to_byte()
  })
  let tail = Bytes::makei(32, i => {
    ((i * 19 + 61) % 233).reinterpret_as_uint().to_byte()
  })
  let input = prefix + a + b + b + a + b + a + b + b + tail

  let frame = compress(input, level=22)
  let block_header = read_u24_le_test(frame, 9)
  assert_eq((block_header >> 1) & 0x3, 2)
  assert_eq(decompress(frame), input)

  let modes = read_first_block_sequence_modes(frame)
  assert_eq(modes, 0xA8)
}

///|
test "compress can emit multi-sequence general RLE block for non-periodic repeats" {
  let chunk_a = Bytes::makei(90, i => {
    ((i * 11 + 37) % 251).reinterpret_as_uint().to_byte()
  })
  let chunk_b = Bytes::makei(90, i => {
    ((i * 13 + 91) % 241).reinterpret_as_uint().to_byte()
  })
  let input = chunk_a + b"|" + chunk_a + b"^" + chunk_b + b"|" + chunk_b + b"$"

  let frame_low = compress(input, level=3)
  let frame_high = compress(input, level=14)
  let block_header = read_u24_le_test(frame_high, 9)
  assert_eq((block_header >> 1) & 0x3, 2)
  assert_true(frame_high.length() < frame_low.length())
  assert_eq(decompress(frame_high), input)

  let seq_count = read_first_block_sequence_count(frame_high)
  assert_true(seq_count >= 2)
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

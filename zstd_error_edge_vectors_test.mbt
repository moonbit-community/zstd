///|
fn assert_corruption_like(
  result : Result[Bytes, ZstdError],
) -> Unit raise Error {
  assert_true(result is Err(CorruptionDetected) || result is Err(SrcSizeWrong))
}

///|
test "edge vectors: truncated direct-huffman literals payload" {
  // Based on the valid direct-Huffman literals frame from zstd_test.
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\xc5\x00\x00\x02\x04\x05\x82\x11\x10\x3d\x34\xf8\xdb\x1b\x6d\x3a\x68\xe4\xed\xe7\x48\xbd\x3c\x27\x9a\x01\x00\xe3\x43\x89\xf5"
  let truncated = frame[:frame.length() - 3].to_bytes()
  let result = try? decompress(truncated)
  assert_corruption_like(result)
}

///|
test "edge vectors: truncated literals Huffman weights FSE section" {
  // Based on the valid FSE-compressed Huffman-weights frame from zstd_test.
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\x55\x01\x00\x02\x84\x09\x05\x30\xfa\x36\x64\x0b\x57\x73\x78\x62\x90\x58\x55\xcd\x78\x86\xdc\xa9\xfd\xe8\x84\x40\x94\xe7\xdd\x3a\xc3\x8c\x64\x99\xf9\xbb\xfa\xb9\x4e\xb9\xcc\x01\x00\x6b\x71\xa5\xdd"
  let truncated = frame[:frame.length() - 5].to_bytes()
  let result = try? decompress(truncated)
  assert_corruption_like(result)
}

///|
test "edge vectors: sequence bitstream truncated after mode header" {
  // Valid predefined-mode sequence frame, then truncate the last bitstream byte.
  let frame = b"\x28\xb5\x2f\xfd\x20\x04\x3d\x00\x00\x08\x61\x01\x00\x00\x10\x02"
  let truncated = frame[:frame.length() - 1].to_bytes()
  let result = try? decompress(truncated)
  assert_corruption_like(result)
}

///|
test "edge vectors: malformed sequence section with overlong count" {
  // Start from a valid one-sequence subset frame, then set Number_of_Sequences
  // to 3 without adding enough sequence payload.
  let frame = b"\x28\xb5\x2f\xfd\x20\x04\x3d\x00\x00\x08\x61\x03\x54\x01\x00\x00"
  let result = try? decompress(frame)
  assert_corruption_like(result)
}

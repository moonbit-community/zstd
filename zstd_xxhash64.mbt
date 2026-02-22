///|
let xxh64_prime1 : UInt64 = 0x9E3779B185EBCA87

///|
let xxh64_prime2 : UInt64 = 0xC2B2AE3D27D4EB4F

///|
let xxh64_prime3 : UInt64 = 0x165667B19E3779F9

///|
let xxh64_prime4 : UInt64 = 0x85EBCA77C2B2AE63

///|
let xxh64_prime5 : UInt64 = 0x27D4EB2F165667C5

///|
fn xxh64(src : Bytes, seed? : UInt64 = (0 : UInt64)) -> UInt64 raise ZstdError {
  let len = src.length()
  let end_pos = len
  let mut pos = 0
  let mut h64 : UInt64 = 0

  if len >= 32 {
    let mut v1 = seed + xxh64_prime1 + xxh64_prime2
    let mut v2 = seed + xxh64_prime2
    let mut v3 = seed
    let mut v4 = seed - xxh64_prime1

    while pos + 32 <= end_pos {
      v1 = xxh64_round(v1, read_u64_le(src, pos))
      v2 = xxh64_round(v2, read_u64_le(src, pos + 8))
      v3 = xxh64_round(v3, read_u64_le(src, pos + 16))
      v4 = xxh64_round(v4, read_u64_le(src, pos + 24))
      pos = pos + 32
    }

    h64 = xxh64_rotl64(v1, 1) +
      xxh64_rotl64(v2, 7) +
      xxh64_rotl64(v3, 12) +
      xxh64_rotl64(v4, 18)
    h64 = xxh64_merge_round(h64, v1)
    h64 = xxh64_merge_round(h64, v2)
    h64 = xxh64_merge_round(h64, v3)
    h64 = xxh64_merge_round(h64, v4)
  } else {
    h64 = seed + xxh64_prime5
  }

  h64 = h64 + len.to_uint64()

  while pos + 8 <= end_pos {
    let k1 = xxh64_round((0 : UInt64), read_u64_le(src, pos))
    h64 = h64 ^ k1
    h64 = xxh64_rotl64(h64, 27) * xxh64_prime1 + xxh64_prime4
    pos = pos + 8
  }

  if pos + 4 <= end_pos {
    h64 = h64 ^ (read_u32_le(src, pos).to_uint64() * xxh64_prime1)
    h64 = xxh64_rotl64(h64, 23) * xxh64_prime2 + xxh64_prime3
    pos = pos + 4
  }

  while pos < end_pos {
    h64 = h64 ^ (src[pos].to_uint().to_uint64() * xxh64_prime5)
    h64 = xxh64_rotl64(h64, 11) * xxh64_prime1
    pos = pos + 1
  }

  xxh64_avalanche(h64)
}

///|
fn xxh64_round(acc : UInt64, input : UInt64) -> UInt64 {
  let mut value = acc + input * xxh64_prime2
  value = xxh64_rotl64(value, 31)
  value * xxh64_prime1
}

///|
fn xxh64_merge_round(acc : UInt64, value : UInt64) -> UInt64 {
  let mut result = acc ^ xxh64_round((0 : UInt64), value)
  result = result * xxh64_prime1 + xxh64_prime4
  result
}

///|
fn xxh64_avalanche(value : UInt64) -> UInt64 {
  let mut h64 = value
  h64 = h64 ^ (h64 >> 33)
  h64 = h64 * xxh64_prime2
  h64 = h64 ^ (h64 >> 29)
  h64 = h64 * xxh64_prime3
  h64 = h64 ^ (h64 >> 32)
  h64
}

///|
fn xxh64_rotl64(value : UInt64, bits : Int) -> UInt64 {
  let b = bits & 63
  if b == 0 {
    value
  } else {
    (value << b) | (value >> (64 - b))
  }
}

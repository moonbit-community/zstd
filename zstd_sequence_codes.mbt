///|
fn literal_length_base_bits(code : UInt) -> (Int, Int) raise ZstdError {
  if code <= 15 {
    (code.reinterpret_as_int(), 0)
  } else if code == 16 {
    (16, 1)
  } else if code == 17 {
    (18, 1)
  } else if code == 18 {
    (20, 1)
  } else if code == 19 {
    (22, 1)
  } else if code == 20 {
    (24, 2)
  } else if code == 21 {
    (28, 2)
  } else if code == 22 {
    (32, 3)
  } else if code == 23 {
    (40, 3)
  } else if code == 24 {
    (48, 4)
  } else if code == 25 {
    (64, 6)
  } else if code == 26 {
    (128, 7)
  } else if code == 27 {
    (256, 8)
  } else if code == 28 {
    (512, 9)
  } else if code == 29 {
    (1024, 10)
  } else if code == 30 {
    (2048, 11)
  } else if code == 31 {
    (4096, 12)
  } else if code == 32 {
    (8192, 13)
  } else if code == 33 {
    (16384, 14)
  } else if code == 34 {
    (32768, 15)
  } else if code == 35 {
    (65536, 16)
  } else {
    raise CorruptionDetected
  }
}

///|
fn match_length_base_bits(code : UInt) -> (Int, Int) raise ZstdError {
  if code <= 31 {
    (code.reinterpret_as_int() + 3, 0)
  } else if code == 32 {
    (35, 1)
  } else if code == 33 {
    (37, 1)
  } else if code == 34 {
    (39, 1)
  } else if code == 35 {
    (41, 1)
  } else if code == 36 {
    (43, 2)
  } else if code == 37 {
    (47, 2)
  } else if code == 38 {
    (51, 3)
  } else if code == 39 {
    (59, 3)
  } else if code == 40 {
    (67, 4)
  } else if code == 41 {
    (83, 4)
  } else if code == 42 {
    (99, 5)
  } else if code == 43 {
    (131, 7)
  } else if code == 44 {
    (259, 8)
  } else if code == 45 {
    (515, 9)
  } else if code == 46 {
    (1027, 10)
  } else if code == 47 {
    (2051, 11)
  } else if code == 48 {
    (4099, 12)
  } else if code == 49 {
    (8195, 13)
  } else if code == 50 {
    (16387, 14)
  } else if code == 51 {
    (32771, 15)
  } else if code == 52 {
    (65539, 16)
  } else {
    raise CorruptionDetected
  }
}

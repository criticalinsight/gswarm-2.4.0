import gleam/bit_array
import gleam/list
import gleam/int

pub type BloomFilter {
  BloomFilter(bits: BitArray, size: Int, hash_count: Int)
}

/// Create a new Bloom Filter with specified size (in bits) and number of hash functions.
pub fn new(size: Int, hash_count: Int) -> BloomFilter {
  let byte_size = case size % 8 {
    0 -> size / 8
    _ -> size / 8 + 1
  }
  BloomFilter(
    bits: bit_array.from_string(string_repeat("0", byte_size)), // Initialize with zeros
    size: byte_size * 8,
    hash_count: hash_count,
  )
}

fn string_repeat(s: String, n: Int) -> String {
  case n <= 0 {
    True -> ""
    False -> s <> string_repeat(s, n - 1)
  }
}

// Better initialization using bit_array directly if possible in Gleam
// Since bit_array.from_string is not ideal for zeros, let's use a byte-based approach
pub fn new_optimized(size_bits: Int, hash_count: Int) -> BloomFilter {
  let byte_size = case size_bits % 8 {
    0 -> size_bits / 8
    _ -> size_bits / 8 + 1
  }
  // Initialize BitArray with zeros using erlang binary:copy if available, 
  // or just create a list of zeros and convert.
  let bits = create_empty_bit_array(byte_size)
  BloomFilter(bits: bits, size: byte_size * 8, hash_count: hash_count)
}

fn create_empty_bit_array(bytes: Int) -> BitArray {
  // Construct a BitArray of N zero bytes
  list.fold(list.repeat(0, bytes), <<>>, fn(acc, byte) {
    <<acc:bits, byte:8>>
  })
}

@external(erlang, "erlang", "phash2")
fn phash2(x: a, range: Int) -> Int

/// Insert a key into the Bloom filter.
pub fn insert(filter: BloomFilter, key: String) -> BloomFilter {
  int.range(from: 1, to: filter.hash_count, with: filter, run: fn(f, i) {
    let index = phash2(#(key, i), f.size)
    let new_bits = set_bit(f.bits, index)
    BloomFilter(..f, bits: new_bits)
  })
}

/// Check if a key might be in the set.
pub fn might_contain(filter: BloomFilter, key: String) -> Bool {
  int.range(from: 1, to: filter.hash_count, with: True, run: fn(acc, i) {
    case acc {
      False -> False
      True -> {
        let index = phash2(#(key, i), filter.size)
        get_bit(filter.bits, index)
      }
    }
  })
}

fn set_bit(bits: BitArray, index: Int) -> BitArray {
  let byte_index = index / 8
  let bit_offset = index % 8
  let bit_size = bit_array.byte_size(bits)
  
  case byte_index >= bit_size {
    True -> bits
    False -> {
      let assert <<prefix:bits-size(byte_index), byte:8, suffix:bits>> = bits
      let new_byte = int.bitwise_or(byte, int.bitwise_shift_left(1, 7 - bit_offset))
      <<prefix:bits, new_byte:8, suffix:bits>>
    }
  }
}

fn get_bit(bits: BitArray, index: Int) -> Bool {
  let byte_index = index / 8
  let bit_offset = index % 8
  let bit_size = bit_array.byte_size(bits)
  
  case byte_index >= bit_size {
    True -> False
    False -> {
      let assert <<_:bits-size(byte_index), byte:8, _:bits>> = bits
      let mask = int.bitwise_shift_left(1, 7 - bit_offset)
      int.bitwise_and(byte, mask) != 0
    }
  }
}

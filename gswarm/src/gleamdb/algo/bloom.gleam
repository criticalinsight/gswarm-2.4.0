import gleam/bit_array
import gleam/list
import gleam/int

pub type BloomFilter {
  BloomFilter(bits: BitArray, size: Int, hash_count: Int)
}

/// Create a new Bloom Filter with specified size (in bits) and number of hash functions.
pub fn new(size_bits: Int, hash_count: Int) -> BloomFilter {
  let byte_size = case size_bits % 8 {
    0 -> size_bits / 8
    _ -> size_bits / 8 + 1
  }
  let bits = list.fold(list.repeat(0, byte_size), <<>>, fn(acc, byte) {
    <<acc:bits, byte:8>>
  })
  BloomFilter(bits: bits, size: byte_size * 8, hash_count: hash_count)
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
  
  case bit_array.byte_size(bits) > byte_index {
    True -> {
      let prefix_bits = byte_index * 8
      let assert <<prefix:bits-size(prefix_bits), byte:8, suffix:bits>> = bits
      let new_byte = int.bitwise_or(byte, int.bitwise_shift_left(1, 7 - bit_offset))
      <<prefix:bits, new_byte:8, suffix:bits>>
    }
    False -> bits
  }
}

fn get_bit(bits: BitArray, index: Int) -> Bool {
  let byte_index = index / 8
  let bit_offset = index % 8
  
  case bit_array.byte_size(bits) > byte_index {
    True -> {
      let prefix_bits = byte_index * 8
      let assert <<_:bits-size(prefix_bits), byte:8, _:bits>> = bits
      let mask = int.bitwise_shift_left(1, 7 - bit_offset)
      int.bitwise_and(byte, mask) != 0
    }
    False -> False
  }
}

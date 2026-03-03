import gleamdb/fact.{type Datom}
import gleamdb/storage.{type StorageAdapter, StorageAdapter}
import simplifile
import gleam/bit_array
import gleam/list

/// A simple append-only disk storage adapter for GClaw.
/// Rich Hickey: "Storage should be a durable record of facts."
pub fn disk(path: String) -> StorageAdapter {
  StorageAdapter(
    init: fn() {
      let _ = simplifile.create_file(path)
      Nil
    },
    persist: fn(d) {
      let bits = fact.encode_datom(d)
      let _ = simplifile.append_bits(path, bits)
      Nil
    },
    persist_batch: fn(ds) {
      let bits =
        list.fold(ds, <<>>, fn(acc, d) {
          bit_array.append(acc, fact.encode_datom(d))
        })
      let _ = simplifile.append_bits(path, bits)
      Nil
    },
    recover: fn() {
      case simplifile.read_bits(path) {
        Ok(bits) -> decode_all(bits, [])
        Error(_) -> Ok([])
      }
    },
  )
}

fn decode_all(bits: BitArray, acc: List(Datom)) -> Result(List(Datom), String) {
  case bit_array.byte_size(bits) == 0 {
    True -> Ok(list.reverse(acc))
    False -> {
      case fact.decode_datom(bits) {
        Ok(#(datom, rest)) -> decode_all(rest, [datom, ..acc])
        Error(_) -> Error("Failed to decode datom stream")
      }
    }
  }
}

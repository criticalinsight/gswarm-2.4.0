import gleam/string
import gleam/list
import gleam/dict.{type Dict}
import gleam/bit_array
import gleam/int
import gleam/float
import gleam/option.{type Option}
import gleam/order

@external(erlang, "erlang", "phash2")
pub fn phash2(data: a) -> Int

pub fn compare(v1: Value, v2: Value) -> order.Order {
  case v1, v2 {
    Int(i1), Int(i2) -> int.compare(i1, i2)
    Float(f1), Float(f2) -> float.compare(f1, f2)
    Str(s1), Str(s2) -> string.compare(s1, s2)
    _, _ -> string.compare(to_string(v1), to_string(v2))
  }
}

pub fn to_string(v: Value) -> String {
  string.inspect(v)
}

pub fn uid(id: Int) -> Eid {
  Uid(EntityId(id))
}

/// Create a deterministic Entity ID based on a hash of the data.
/// This enables idempotent transaction semantics.
pub fn deterministic_uid(data: a) -> Eid {
  Uid(EntityId(phash2(data)))
}

pub fn ref(id: Int) -> EntityId {
  EntityId(id)
}

pub fn eid_to_integer(eid: EntityId) -> Int {
  let EntityId(i) = eid
  i
}

/// Create a unique, deterministic Entity ID for an event based on its type and timestamp.
/// This ensures that the same event instance (e.g. from retries) always gets the same ID.
pub fn event_uid(event_type: String, timestamp: Int) -> Eid {
  deterministic_uid(#(event_type, timestamp))
}

pub type EntityId {
  EntityId(Int)
}

pub type Entity =
  EntityId

pub type Attribute = String
pub type Transaction = Int

pub type DbFunction(state) =
  fn(state, Int, Int, List(Value)) -> List(Fact)

pub type LookupRef = #(Attribute, Value)

pub type Eid {
  Lookup(LookupRef)
  Uid(EntityId)
}

pub type Value {
  Str(String)
  Int(Int)
  Float(Float)
  Bool(Bool)
  List(List(Value))
  Vec(List(Float))
  Ref(EntityId)
  Map(Dict(String, Value))
  Blob(BitArray)
}

pub type Operation {
  Assert
  Retract
}

pub type StorageLayout {
  Row
  Columnar
}

pub type Retention {
  All
  LatestOnly
  Last(Int)
}

pub type StorageTier {
  Memory
  Disk
  Cloud
}

pub type EvictionPolicy {
  AlwaysInMemory
  LruToDisk
  LruToCloud
}

pub type Cardinality {
  Many
  One
}

pub type AttributeConfig {
  AttributeConfig(
    unique: Bool,
    component: Bool,
    retention: Retention,
    cardinality: Cardinality,
    check: Option(String),
    composite_group: Option(String),
    layout: StorageLayout,
    tier: StorageTier,
    eviction: EvictionPolicy,
  )
}

pub type CrackingNode {
  Leaf(values: List(Value))
  Branch(pivot: Value, left: CrackingNode, right: CrackingNode)
}

pub type ColumnChunk {
  ColumnChunk(
    attribute: Attribute,
    values: CrackingNode,
    stats: Dict(String, Value),
  )
}

/// A Fact is #(Eid, Attribute, Value) for assertion,
/// or a more explicit Tuple for retractions.
pub type Fact = #(Eid, Attribute, Value)

pub type Datom {
  Datom(
    entity: Entity,
    attribute: Attribute,
    value: Value,
    tx: Transaction,
    tx_index: Int,
    valid_time: Int,
    operation: Operation,
  )
}

pub fn to_uid(id: EntityId) -> Eid {
  Uid(id)
}

/// Create a new Datom with default valid_time = 0.
pub fn new_datom(
  entity entity: Entity,
  attribute attribute: Attribute,
  value value: Value,
  tx tx: Transaction,
  tx_index tx_index: Int,
  operation operation: Operation,
) -> Datom {
  Datom(entity, attribute, value, tx, tx_index, 0, operation)
}

pub fn encode_compact(v: Value) -> BitArray {
  case v {
    Str(s) -> {
      let b = <<s:utf8>>
      <<0:8, {byte_size(b)}:32, b:bits>>
    }
    Int(i) -> <<1:8, i:64>>
    Float(f) -> <<2:8, f:float>>
    Bool(b) -> <<3:8, {case b { True -> 1 False -> 0 }}:8>>
    List(l) -> {
      let b = list.fold(l, <<>>, fn(acc, item) { <<acc:bits, {encode_compact(item)}:bits>> })
      <<4:8, {list.length(l)}:32, b:bits>>
    }
    Vec(v) -> {
      let b = list.fold(v, <<>>, fn(acc, item) { <<acc:bits, item:float>> })
      <<5:8, {list.length(v)}:32, b:bits>>
    }
    Ref(EntityId(id)) -> <<6:8, id:64>>
    Map(m) -> {
      let b = dict.fold(m, <<>>, fn(acc, key, val) {
        let k_bits = <<key:utf8>>
        <<acc:bits, {string.length(key)}:32, k_bits:bits, {encode_compact(val)}:bits>>
      })
      <<7:8, {dict.size(m)}:32, b:bits>>
    }
    Blob(bin) -> <<8:8, {byte_size(bin)}:32, bin:bits>>
  }
}

@external(erlang, "erlang", "byte_size")
fn byte_size(bits: BitArray) -> Int

pub fn encode_datom(d: Datom) -> BitArray {
  let EntityId(e_id) = d.entity
  let op_id = case d.operation {
    Assert -> 1
    Retract -> 0
  }
  let v_bits = encode_compact(d.value)
  let a_bits = <<{d.attribute}:utf8>>
  
  <<
    e_id:64,
    {byte_size(a_bits)}:32, a_bits:bits,
    op_id:8,
    d.tx:64,
    d.tx_index:32,
    d.valid_time:64,
    v_bits:bits
  >>
}

pub fn decode_compact(bits: BitArray) -> Result(#(Value, BitArray), Nil) {
  case bits {
    <<0:8, len:32, s:bytes-size(len), rest:bits>> -> {
      case bit_array.to_string(s) {
        Ok(str) -> Ok(#(Str(str), rest))
        Error(_) -> Error(Nil)
      }
    }
    <<1:8, i:64, rest:bits>> -> Ok(#(Int(i), rest))
    <<2:8, f:float, rest:bits>> -> Ok(#(Float(f), rest))
    <<3:8, b:8, rest:bits>> -> Ok(#(Bool(b == 1), rest))
    <<4:8, len:32, rest:bits>> -> {
      case decode_list_loop(rest, len, []) {
        Ok(#(l, tail)) -> Ok(#(List(list.reverse(l)), tail))
        Error(_) -> Error(Nil)
      }
    }
    <<5:8, len:32, rest:bits>> -> {
      case decode_vec_loop(rest, len, []) {
        Ok(#(v, tail)) -> Ok(#(Vec(list.reverse(v)), tail))
        Error(_) -> Error(Nil)
      }
    }
    <<6:8, id:64, rest:bits>> -> Ok(#(Ref(EntityId(id)), rest))
    <<7:8, len:32, rest:bits>> -> {
      case decode_map_loop(rest, len, dict.new()) {
        Ok(#(m, tail)) -> Ok(#(Map(m), tail))
        Error(_) -> Error(Nil)
      }
    }
    <<8:8, len:32, bin:bytes-size(len), rest:bits>> -> Ok(#(Blob(bin), rest))
    _ -> Error(Nil)
  }
}

fn decode_map_loop(bits: BitArray, len: Int, acc: Dict(String, Value)) -> Result(#(Dict(String, Value), BitArray), Nil) {
  case len {
    0 -> Ok(#(acc, bits))
    _ -> {
      case bits {
        <<k_len:32, k_bits:bytes-size(k_len), rest:bits>> -> {
          case bit_array.to_string(k_bits) {
            Ok(key) -> {
              case decode_compact(rest) {
                Ok(#(val, tail)) -> decode_map_loop(tail, len - 1, dict.insert(acc, key, val))
                Error(_) -> Error(Nil)
              }
            }
            Error(_) -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    }
  }
}

fn decode_list_loop(bits: BitArray, len: Int, acc: List(Value)) -> Result(#(List(Value), BitArray), Nil) {
  case len {
    0 -> Ok(#(acc, bits))
    _ -> {
      case decode_compact(bits) {
        Ok(#(val, rest)) -> decode_list_loop(rest, len - 1, [val, ..acc])
        Error(_) -> Error(Nil)
      }
    }
  }
}

fn decode_vec_loop(bits: BitArray, len: Int, acc: List(Float)) -> Result(#(List(Float), BitArray), Nil) {
  case len {
    0 -> Ok(#(acc, bits))
    _ -> {
      case bits {
        <<f:float, rest:bits>> -> decode_vec_loop(rest, len - 1, [f, ..acc])
        _ -> Error(Nil)
      }
    }
  }
}

pub fn decode_datom(bits: BitArray) -> Result(#(Datom, BitArray), Nil) {
  case bits {
    <<e_id:64, a_len:32, a_bits:bytes-size(a_len), op_id:8, tx:64, txi:32, vt:64,
      val_bits:bits>> -> {
      case bit_array.to_string(a_bits) {
        Ok(attr) -> {
          let op = case op_id {
            1 -> Assert
            _ -> Retract
          }
          case decode_compact(val_bits) {
            Ok(#(val, rest)) -> {
              Ok(#(
                Datom(
                  entity: EntityId(e_id),
                  attribute: attr,
                  value: val,
                  tx: tx,
                  tx_index: txi,
                  valid_time: vt,
                  operation: op,
                ),
                rest,
              ))
            }
            Error(_) -> Error(Nil)
          }
        }
        Error(_) -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

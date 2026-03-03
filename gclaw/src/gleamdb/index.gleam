import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleamdb/fact.{type Datom, type Entity, type Attribute, type Value}

pub type Index =
  Dict(fact.EntityId, List(Datom))

pub type AIndex =
  Dict(String, List(Datom))

pub type AVIndex =
  Dict(String, Dict(Value, Entity))

/// A hybrid index that keeps a hot cache in memory and offloads to disk
pub type HybridIndex {
  HybridIndex(
    hot: Index,
    cold: List(BitArray), // Simplified cold storage for now
    capacity: Int,
  )
}

pub fn new_index() -> Index {
  dict.new()
}

pub fn new_aindex() -> AIndex {
  dict.new()
}

pub fn new_avindex() -> AVIndex {
  dict.new()
}

pub fn new_hybrid_index(capacity: Int) -> HybridIndex {
  HybridIndex(hot: dict.new(), cold: [], capacity: capacity)
}

pub fn insert_hybrid(
  index: HybridIndex,
  datom: Datom,
  retention: fact.Retention,
) -> HybridIndex {
  let new_index = insert_eavt(index.hot, datom, retention)
  
  // Check capacity - if we exceed, we should flush
  // For simplicity, we flush the oldest if we exceed capacity
  case dict.size(new_index) > index.capacity {
    True -> {
      // Find oldest entity or attribute to flush
      // Simplified: Just keep the hot as is but encode the historical datoms
      // In a real system we would selectively flush.
      index
    }
    False -> HybridIndex(..index, hot: new_index)
  }
}

pub fn insert_eavt(index: Index, datom: Datom, retention: fact.Retention) -> Index {
  let bucket = dict.get(index, datom.entity) |> result_to_list
  let new_bucket = case retention {
    fact.All -> [datom, ..bucket]
    fact.LatestOnly -> {
      // Filter out existing datoms for this attribute
      let filtered = list.filter(bucket, fn(d) { d.attribute != datom.attribute })
      [datom, ..filtered]
    }
    fact.Last(n) -> {
      let filtered = list.filter(bucket, fn(d) { d.attribute != datom.attribute })
      let existing = list.filter(bucket, fn(d) { d.attribute == datom.attribute })
      let kept = list.take(existing, n - 1)
      [datom, ..list.append(kept, filtered)]
    }
  }
  dict.insert(index, datom.entity, new_bucket)
}

pub fn insert_aevt(index: AIndex, datom: Datom, retention: fact.Retention) -> AIndex {
  let bucket = dict.get(index, datom.attribute) |> result_to_list
  let new_bucket = case retention {
    fact.All -> [datom, ..bucket]
    fact.LatestOnly -> {
      // Latest per entity for this attribute
      let filtered = list.filter(bucket, fn(d) { d.entity != datom.entity })
      [datom, ..filtered]
    }
    fact.Last(n) -> {
      let filtered = list.filter(bucket, fn(d) { d.entity != datom.entity })
      let existing = list.filter(bucket, fn(d) { d.entity == datom.entity })
      let kept = list.take(existing, n - 1)
      [datom, ..list.append(kept, filtered)]
    }
  }
  dict.insert(index, datom.attribute, new_bucket)
}

pub fn insert_avet(index: AVIndex, datom: Datom) -> AVIndex {
  let v_dict = dict.get(index, datom.attribute) |> result.unwrap(dict.new())
  let new_v_dict = dict.insert(v_dict, datom.value, datom.entity)
  dict.insert(index, datom.attribute, new_v_dict)
}

pub fn delete_eavt(index: Index, datom: Datom) -> Index {
  insert_eavt(index, datom, fact.All)
}

pub fn delete_aevt(index: AIndex, datom: Datom) -> AIndex {
  insert_aevt(index, datom, fact.All)
}

pub fn delete_avet(index: AVIndex, datom: Datom) -> AVIndex {
  let v_dict = dict.get(index, datom.attribute) |> result.unwrap(dict.new())
  let new_v_dict = dict.delete(v_dict, datom.value)
  dict.insert(index, datom.attribute, new_v_dict)
}

fn result_to_list(res: Result(List(a), b)) -> List(a) {
  case res {
    Ok(l) -> l
    Error(_) -> []
  }
}

pub fn filter_by_attribute(index: AIndex, attr: Attribute) -> List(Datom) {
  dict.get(index, attr) |> result_to_list
}

pub fn filter_by_entity(index: Index, entity: fact.EntityId) -> List(Datom) {
  dict.get(index, entity) |> result_to_list
}

pub fn get_datoms_by_entity_attr_val(
  index: Index,
  entity: fact.EntityId,
  attr: Attribute,
  val: Value,
) -> List(Datom) {
  dict.get(index, entity)
  |> result_to_list
  |> list.filter(fn(d) { d.attribute == attr && d.value == val })
}

pub fn get_datoms_by_entity_attr(
  index: Index,
  entity: fact.EntityId,
  attr: Attribute,
) -> List(Datom) {
  dict.get(index, entity)
  |> result_to_list
  |> list.filter(fn(d) { d.attribute == attr })
}

pub fn get_datoms_by_val(index: AIndex, attr: Attribute, val: Value) -> List(Datom) {
  dict.get(index, attr)
  |> result_to_list
  |> list.filter(fn(d) { d.value == val })
}

pub fn get_all_datoms(index: Index) -> List(Datom) {
  dict.values(index)
  |> list.flatten()
}

pub fn get_all_datoms_for_attr(index: Index, attr: Attribute) -> List(Datom) {
  dict.values(index)
  |> list.flatten()
  |> list.filter(fn(d) { d.attribute == attr })
}

pub fn get_all_datoms_avet(index: AVIndex) -> List(Datom) {
  dict.values(index)
  |> list.flat_map(fn(v_dict) {
    dict.to_list(v_dict)
    |> list.map(fn(pair) {
      let #(val, eid) = pair
      fact.Datom(entity: eid, attribute: "unknown", value: val, tx: 0, valid_time: 0, operation: fact.Assert)
    })
  })
}

pub fn get_entity_by_av(index: AVIndex, attr: Attribute, val: Value) -> Result(fact.EntityId, Nil) {
  case dict.get(index, attr) {
    Ok(v_dict) -> dict.get(v_dict, val)
    Error(_) -> Error(Nil)
  }
}

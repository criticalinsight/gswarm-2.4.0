import gleamdb/fact.{type Datom}

pub type StorageAdapter {
  StorageAdapter(
    init: fn() -> Nil,
    persist: fn(Datom) -> Nil,
    persist_batch: fn(List(Datom)) -> Nil,
    recover: fn() -> Result(List(Datom), String),
  )
}
pub fn ephemeral() -> StorageAdapter {
  StorageAdapter(
    init: fn() { Nil },
    persist: fn(_) { Nil },
    persist_batch: fn(_) { Nil },
    recover: fn() { Ok([]) },
  )
}

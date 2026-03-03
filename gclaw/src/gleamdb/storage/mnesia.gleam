import gleamdb/fact.{type Datom}
import gleamdb/storage.{type StorageAdapter, StorageAdapter}

@external(erlang, "gleamdb_mnesia_ffi", "init")
pub fn init_mnesia() -> Nil

@external(erlang, "gleamdb_mnesia_ffi", "persist")
pub fn persist_datom(datom: Datom) -> Nil

@external(erlang, "gleamdb_mnesia_ffi", "persist_batch")
pub fn persist_batch(datoms: List(Datom)) -> Nil

pub fn adapter() -> StorageAdapter {
  StorageAdapter(
    init: init_mnesia,
    persist: persist_datom,
    persist_batch: persist_batch,
    recover: recover_datoms,
  )
}

@external(erlang, "gleamdb_mnesia_ffi", "recover")
pub fn recover_datoms() -> Result(List(Datom), String)

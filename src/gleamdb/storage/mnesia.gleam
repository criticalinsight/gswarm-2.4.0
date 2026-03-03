import gleamdb/fact.{type Datom}
import gleamdb/storage.{StorageAdapter}

@external(erlang, "gleamdb_mnesia_ffi", "init")
pub fn init_mnesia() -> Nil

@external(erlang, "gleamdb_mnesia_ffi", "persist")
pub fn persist_datom(datom: Datom) -> Nil

@external(erlang, "gleamdb_mnesia_ffi", "persist_batch")
pub fn persist_batch(datoms: List(Datom)) -> Nil

pub fn adapter() -> storage.StorageAdapter {
  storage.StorageAdapter(
    insert: fn(datoms) {
       persist_batch(datoms)
       Ok(Nil)
    },
    append: fn(datoms) {
       persist_batch(datoms)
       Ok(Nil)
    },
    read: fn(_attr) {
       recover_datoms()
    },
    read_all: fn() {
       recover_datoms()
    },
  )
}

@external(erlang, "gleamdb_mnesia_ffi", "recover")
pub fn recover_datoms() -> Result(List(Datom), String)

import gleamdb/fact

pub type StorageAdapter {
  StorageAdapter(
    insert: fn(List(fact.Datom)) -> Result(Nil, String),
    append: fn(List(fact.Datom)) -> Result(Nil, String),
    read: fn(String) -> Result(List(fact.Datom), String),
    read_all: fn() -> Result(List(fact.Datom), String),
  )
}

pub fn insert(adapter: StorageAdapter, datoms: List(fact.Datom)) -> Result(Nil, String) {
  adapter.insert(datoms)
}

pub fn append(adapter: StorageAdapter, datoms: List(fact.Datom)) -> Result(Nil, String) {
  adapter.append(datoms)
}

pub fn read_all(adapter: StorageAdapter) -> Result(List(fact.Datom), String) {
  adapter.read_all()
}

pub fn ephemeral() -> StorageAdapter {
  StorageAdapter(
    insert: fn(_) { Ok(Nil) },
    append: fn(_) { Ok(Nil) },
    read: fn(_) { Ok([]) },
    read_all: fn() { Ok([]) },
  )
}

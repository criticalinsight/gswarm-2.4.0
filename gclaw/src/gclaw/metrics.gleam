import gleam/dynamic
import gleamdb/shared/types
import gleamdb/fact

pub fn new_adapter() -> types.IndexAdapter {
  types.IndexAdapter(
    name: "metric",
    create: create,
    update: update,
    search: search,
  )
}

fn create(_attribute: String) -> dynamic.Dynamic {
  dynamic.nil() // Placeholder state
}

fn update(data: dynamic.Dynamic, _datoms: List(fact.Datom)) -> dynamic.Dynamic {
  data // No-op for now
}

fn search(_data: dynamic.Dynamic, _query: types.IndexQuery, _threshold: Float) -> List(fact.EntityId) {
  [] // No-op search
}

# Data Federation (Virtual Predicates)

Data Federation allows GleamDB to query external data sources (CSV files, JSON APIs, or even other databases) as if they were native facts.

## Design: Virtual Predicates
Virtual predicates are registered at runtime as adapters. When the query engine encounters a `Virtual` clause, it delegates row generation to the adapter.

### The Adapter Interface
An adapter is a function that takes a list of resolved values (arguments) and returns a list of result rows (each row is a list of values).

```gleam
pub type VirtualAdapter =
  fn(List(fact.Value)) -> List(List(fact.Value))
```

## Usage

### 1. Register an Adapter
Register a function that "solves" the virtual predicate.

```gleam
import gleamdb
import gleamdb/fact

let csv_adapter = fn(args) {
  // Logic to read CSV based on args
  [[fact.Str("Alice"), fact.Int(30)], [fact.Str("Bob"), fact.Int(25)]]
}

gleamdb.register_virtual(db, "users_csv", csv_adapter)
```

### 2. Query the Virtual Predicate
Join external data with internal database facts in a single Datalog query.

```gleam
import gleamdb/q

let query = q.new()
  |> q.virtual("users_csv", [], ["name", "age"]) // Fetch from external
  |> q.where(q.v("e"), "user/name", q.v("name"))   // Join with internal
  |> q.to_clauses()
```

## Benefits
- **Zero ETL**: Access external data in real-time without complex ingestion pipelines.
- **De-complected Storage**: The query engine doesn't care if the data is in an ETS table or a remote file.
- **Declarative Power**: Use Datalog's filtering, joining, and aggregation capabilities on external data.

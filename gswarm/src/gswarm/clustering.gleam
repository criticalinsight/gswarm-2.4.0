import gleam/list
import gleam/io
import gleam/dict
import gleam/erlang/process
import gleamdb
import gleamdb/fact
import gleamdb/shared/types.{Aggregate, Avg, Positive, Similarity, Var}

pub fn start_clustering_loop(db: gleamdb.Db, interval_ms: Int) {
  process.spawn_unlinked(fn() {
    loop(db, interval_ms)
  })
}

fn loop(db: gleamdb.Db, interval_ms: Int) {
  process.sleep(interval_ms)
  run_clustering_cycle(db)
  loop(db, interval_ms)
}

pub fn run_clustering_cycle(db: gleamdb.Db) {
  io.println("🧠 Clustering Oracle: Starting behavioral analysis for 50k traders...")
  
  // 1. Fetch some seeds (or use existing centroids)
  // For simplicity in this phase, we use 5 fixed qualitative archetypes as initial centroids:
  // [Concentration, Agility, Conviction, Accuracy]
  let initial_centroids = [
    #("c1", "Institutional Insider", [0.1, 0.9, 0.9, 0.9]),
    #("c2", "Reactive Momentum", [0.8, 0.8, 0.4, 0.6]),
    #("c3", "Diversified Alpha", [0.9, 0.5, 0.5, 0.8]),
    #("c4", "High-Frequency Noise", [0.2, 0.9, 0.1, 0.4]),
    #("c5", "Passive Liquidity", [0.5, 0.1, 0.1, 0.5])
  ]
  
  // 2. Assign & Aggregate using Datalog
  list.each(initial_centroids, fn(c) {
    let #(cid, label, vec) = c
    
    // Find all traders similar to this centroid and calculate their average vector
    // This is a "Speculative Centroid" step
    let query = [
      Aggregate(
        "v", 
        Avg, 
        "mean_vec", 
        [
          Positive(#(Var("t"), "trader/strategy_vector", Var("v"))),
          Similarity("v", vec, 0.8)
        ]
      )
    ]
    
    let results = gleamdb.query(db, query)
    case list.first(results.rows) {
        Ok(_bindings) -> {
            // In a full K-means we would iterate. Here we just tag the cohort.
            tag_cohort(db, cid, label, vec)
        }
        Error(_) -> Nil
    }
  })
}

fn tag_cohort(db: gleamdb.Db, _cid: String, label: String, centroid_vec: List(Float)) {
    // Tag all traders within 0.8 similarity of this centroid with the label
    let query = [
      Positive(#(Var("t"), "trader/strategy_vector", Var("v"))),
      Similarity("v", centroid_vec, 0.8)
    ]
    
    let traders = gleamdb.query(db, query).rows
    let facts = list.filter_map(traders, fn(row) {
        case dict.get(row, "t") {
            Ok(t_val) -> {
                case t_val {
                    fact.Ref(eid) -> Ok(#(fact.Uid(eid), "trader/behavioral_tag", fact.Str(label)))
                    _ -> Error(Nil)
                }
            }
            Error(_) -> Error(Nil)
        }
    })
    
    let _ = gleamdb.transact(db, facts)
    Nil
}

import gleam/result
import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import gleam/dict
import gswarm/shard_manager.{type ShardRegistry}
import gswarm/cms.{type CMS}
import gswarm/hll.{type HLL}

pub type Message {
  RecordMarket(market_id: String)
  GetRegistry(Subject(ShardRegistry))
  GetHotMarkets(Subject(List(#(String, Int))))
  GetCardinality(Subject(Int))
  GetFrequency(market_id: String, reply_to: Subject(Int))
  CollapseShard(virtual_id: Int, physical_id: Int)
  GetMetrics(Subject(Metrics))
}

pub type Metrics {
  Metrics(
    hll_cardinality: Int,
    shard_count: Int,
    bloom_size_bits: Int
  )
}

pub type RegistryState {
  RegistryState(
    registry: ShardRegistry,
    frequency: CMS,
    cardinality: HLL
  )
}

pub fn start(shard_count: Int) -> Result(Subject(Message), actor.StartError) {
  let initial_state = RegistryState(
    registry: shard_manager.new_registry(shard_count),
    frequency: cms.new(1000, 3),
    cardinality: hll.new(10)
  )
  
  actor.new(initial_state)
  |> actor.on_message(fn(state, msg) {
    case msg {
      RecordMarket(mid) -> {
        let new_registry = shard_manager.record_market(state.registry, mid)
        let new_freq = cms.increment(state.frequency, mid)
        let new_card = hll.insert(state.cardinality, mid)
        actor.continue(RegistryState(new_registry, new_freq, new_card))
      }
      GetRegistry(reply_to) -> {
        process.send(reply_to, state.registry)
        actor.continue(state)
      }
      GetHotMarkets(reply_to) -> {
        process.send(reply_to, [])
        actor.continue(state)
      }
      GetCardinality(reply_to) -> {
        process.send(reply_to, hll.estimate(state.cardinality))
        actor.continue(state)
      }
      GetFrequency(mid, reply_to) -> {
        process.send(reply_to, cms.estimate(state.frequency, mid))
        actor.continue(state)
      }
      CollapseShard(vid, pid) -> {
        let new_registry = shard_manager.ShardRegistry(
          ..state.registry,
          shard_map: dict.insert(state.registry.shard_map, vid, pid)
        )
        actor.continue(RegistryState(..state, registry: new_registry))
      }
      GetMetrics(reply_to) -> {
        let card = hll.estimate(state.cardinality)
        let shards = state.registry.shard_count
        // Get bloom size from first shard if available, else default (e.g. 10000 from shard_manager)
        let bloom_size = case dict.get(state.registry.filters, 0) {
           Ok(f) -> f.size
           Error(_) -> 0
        }
        
        process.send(reply_to, Metrics(card, shards, bloom_size))
        actor.continue(state)
      }
    }
  })
  |> actor.start()
  |> result_map_data()
}

fn result_map_data(res: Result(actor.Started(Subject(Message)), actor.StartError)) -> Result(Subject(Message), actor.StartError) {
  result.map(res, fn(started) { started.data })
}

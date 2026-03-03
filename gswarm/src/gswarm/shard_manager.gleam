import gswarm/bloom.{type BloomFilter}
import gleam/dict.{type Dict}
import gleam/int

/// Shard Manager (Phase 39).
/// Rich Hickey: "De-complecting the market processing allows the swarm to scale horizontally."

@external(erlang, "erlang", "phash2")
pub fn phash2(x: a) -> Int

/// Deterministically maps a market_id to a shard index [0..shard_count-1].
pub fn get_shard_id(market_id: String, shard_count: Int) -> Int {
  case shard_count <= 1 {
    True -> 0
    False -> {
      let hash = phash2(market_id)
      hash % shard_count
    }
  }
}

/// Maps a virtual shard ID to its current physical shard ID (respecting collapsing).
pub fn resolve_physical_shard(registry: ShardRegistry, virtual_shard_id: Int) -> Int {
  case dict.get(registry.shard_map, virtual_shard_id) {
    Ok(physical) -> physical
    Error(_) -> virtual_shard_id
  }
}

pub type ShardRegistry {
  ShardRegistry(
    filters: Dict(Int, BloomFilter),
    /// Mapping of virtual shard ID to physical shard ID
    shard_map: Dict(Int, Int),
    shard_count: Int
  )
}

pub fn new_registry(shard_count: Int) -> ShardRegistry {
  let filters = dict.new()
  let shard_map = dict.new()
  // Bloom filter: 10k bits, 3 hashes
  let filters =
    int.range(from: 0, to: shard_count, with: filters, run: fn(acc, i) {
      dict.insert(acc, i, bloom.new_optimized(10_000, 3))
    })
  let shard_map =
    int.range(from: 0, to: shard_count, with: shard_map, run: fn(acc, i) {
      dict.insert(acc, i, i)
    })
  ShardRegistry(filters: filters, shard_map: shard_map, shard_count: shard_count)
}

pub fn record_market(registry: ShardRegistry, market_id: String) -> ShardRegistry {
  let virtual_id = get_shard_id(market_id, registry.shard_count)
  let physical_id = resolve_physical_shard(registry, virtual_id)
  let assert Ok(filter) = dict.get(registry.filters, physical_id)
  let new_filter = bloom.insert(filter, market_id)
  ShardRegistry(..registry, filters: dict.insert(registry.filters, physical_id, new_filter))
}

pub fn market_might_exist(registry: ShardRegistry, market_id: String) -> Bool {
  let virtual_id = get_shard_id(market_id, registry.shard_count)
  let physical_id = resolve_physical_shard(registry, virtual_id)
  case dict.get(registry.filters, physical_id) {
    Ok(filter) -> bloom.might_contain(filter, market_id)
    Error(_) -> False
  }
}

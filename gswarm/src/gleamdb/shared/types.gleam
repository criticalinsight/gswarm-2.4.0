import gleam/dict.{type Dict}
import gleam/option.{type Option}
import gleamdb/algo/bloom
import gleam/erlang/process.{type Subject}
import gleamdb/fact.{type AttributeConfig, type Datom, type DbFunction}
import gleamdb/index.{type Index, type AIndex, type AVIndex}
import gleamdb/storage.{type StorageAdapter}
import gleamdb/raft
import gleamdb/vec_index
import gleamdb/index/art
import gleamdb/index/bm25
import gleam/dynamic.{type Dynamic}

pub type IndexAdapter {
  IndexAdapter(
    name: String,
    create: fn(String) -> Dynamic,
    update: fn(Dynamic, List(Datom)) -> Dynamic,
    search: fn(Dynamic, IndexQuery, Float) -> List(fact.EntityId),
  )
}

pub type ExtensionInstance {
  ExtensionInstance(
    adapter_name: String,
    attribute: String,
    data: Dynamic,
  )
}

pub type Config {
  Config(parallel_threshold: Int, batch_size: Int)
}

pub type DbState {
  DbState(
    adapter: StorageAdapter,
    eavt: Index,
    aevt: AIndex,
    avet: AVIndex,
    latest_tx: Int,
    subscribers: List(Subject(List(Datom))),
    schema: Dict(String, AttributeConfig),
    functions: Dict(String, DbFunction(DbState)),
    composites: List(List(String)),
    reactive_actor: Subject(ReactiveMessage),
    followers: List(process.Pid),
    is_distributed: Bool,
    ets_name: Option(String),
    raft_state: raft.RaftState,
    vec_index: vec_index.VecIndex,
    bm25_indices: Dict(String, bm25.BM25Index),
    art_index: art.Art,
    // Tier 2: Extension Registry
    registry: Dict(String, IndexAdapter),
    extensions: Dict(String, ExtensionInstance),
    predicates: Dict(String, fn(fact.Value) -> Bool),
    stored_rules: List(Rule),
    virtual_predicates: Dict(String, VirtualAdapter),
    config: Config,
  )
}

pub type VirtualAdapter =
  fn(List(fact.Value)) -> List(List(fact.Value))

pub type Clause =
  #(Part, String, Part)

pub type IndexQuery {
  TextQuery(text: String)
  NumericRange(min: Float, max: Float)
  Custom(data: String) // Placeholder for dynamic/any until supported
}

pub type Part {
  Var(String)
  Val(fact.Value)
}

pub type BodyClause {
  Positive(Clause)
  Negative(Clause)
  Filter(Expression)
  Bind(String, fn(Dict(String, fact.Value)) -> fact.Value)
  Aggregate(
    variable: String,
    function: AggFunc,
    target: String,
    filter: List(BodyClause),
  )

  StartsWith(variable: String, prefix: String)
  Similarity(variable: String, vector: List(Float), threshold: Float)
  SimilarityEntity(variable: String, vector: List(Float), threshold: Float)
  BM25(
    variable: String,
    attribute: String,
    query: String,
    threshold: Float,
    k1: Float,
    b: Float,
  )
  CustomIndex(
    variable: String,
    index_name: String,
    query:  IndexQuery,
    threshold: Float,
  )
  Temporal(
    variable: String,
    entity: Part,
    attribute: String,
    start: Int,
    end: Int,
    basis: TemporalType,
  )
  Limit(n: Int)
  Offset(n: Int)
  OrderBy(variable: String, direction: OrderDirection)
  GroupBy(variable: String)
  ShortestPath(
    from: Part,
    to: Part,
    edge: String,
    path_var: String,
    cost_var: Option(String),
  )
  PageRank(
    entity_var: String,
    edge: String,
    rank_var: String,
    dumping_factor: Float,
    iterations: Int,
  )
  Virtual(
    predicate: String,
    args: List(Part),
    outputs: List(String),
  )
  Reachable(
    from: Part,
    edge: String,
    node_var: String,
  )
  ConnectedComponents(
    edge: String,
    entity_var: String,
    component_var: String,
  )
  Neighbors(
    from: Part,
    edge: String,
    depth: Int,
    node_var: String,
  )
  CycleDetect(
    edge: String,
    cycle_var: String,
  )
  BetweennessCentrality(
    edge: String,
    entity_var: String,
    score_var: String,
  )
  TopologicalSort(
    edge: String,
    entity_var: String,
    order_var: String,
  )
  StronglyConnectedComponents(
    edge: String,
    entity_var: String,
    component_var: String,
  )
  BloomJoin(
    variable: String,
    clauses: List(BodyClause),
  )
  BloomFilter(
    variable: String,
    filter: bloom.BloomFilter,
  )
}

pub type Rule {
  Rule(head: Clause, body: List(BodyClause))
}

pub type TemporalType {
  Tx
  Valid
}

pub type OrderDirection {
  Asc
  Desc
}

pub type AggFunc {
  Sum
  Count
  Min
  Max
  Avg
  Median
}

pub type SpeculativeResult {
  SpeculativeResult(
    state: DbState,
    datoms: List(fact.Datom),
  )
}

pub type QueryMetadata {
  QueryMetadata(
    tx_id: Option(Int),
    valid_time: Option(Int),
    execution_time_ms: Int,
    shard_id: Option(Int),
    aggregates: Dict(String, AggFunc),
  )
}

pub type QueryResult {
  QueryResult(
    rows: List(Dict(String, fact.Value)),
    metadata: QueryMetadata,
  )
}

pub type ReactiveMessage {
  Subscribe(
    query: List(BodyClause),
    attributes: List(String),
    subscriber: Subject(ReactiveDelta),
    initial_state: QueryResult,
  )
  Notify(changed_attributes: List(String), current_state: DbState)
}

pub type ReactiveDelta {
  Initial(QueryResult)
  Delta(added: QueryResult, removed: QueryResult)
}

pub type Expression {
  Eq(Part, Part)
  Neq(Part, Part)
  Gt(Part, Part)
  Lt(Part, Part)
  And(Expression, Expression)
  Or(Expression, Expression)
}

pub fn eid_to_integer(id: fact.EntityId) -> Int {
  let fact.EntityId(i) = id
  i
}

pub fn integer_to_eid(i: Int) -> fact.EntityId {
  fact.EntityId(i)
}

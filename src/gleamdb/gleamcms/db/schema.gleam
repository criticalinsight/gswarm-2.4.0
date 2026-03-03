import gleam/option.{None}
import gleamdb
import gleamdb/fact.{AttributeConfig, Many, One, All}

pub fn init_schema(db: gleamdb.Db) {
  let _ = gleamdb.set_schema(db, "cms.post/title", AttributeConfig(unique: False, component: False, retention: All, cardinality: One, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  let _ = gleamdb.set_schema(db, "cms.post/slug", AttributeConfig(unique: True, component: False, retention: All, cardinality: One, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  let _ = gleamdb.set_schema(db, "cms.post/content", AttributeConfig(unique: False, component: False, retention: All, cardinality: One, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  let _ = gleamdb.set_schema(db, "cms.post/status", AttributeConfig(unique: False, component: False, retention: All, cardinality: One, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  let _ = gleamdb.set_schema(db, "cms.post/published_at", AttributeConfig(unique: False, component: False, retention: All, cardinality: One, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  let _ = gleamdb.set_schema(db, "cms.post/tags", AttributeConfig(unique: False, component: False, retention: All, cardinality: Many, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  let _ = gleamdb.set_schema(db, "cms.post/featured_image", AttributeConfig(unique: False, component: False, retention: All, cardinality: One, check: None, composite_group: None, layout: fact.Row, tier: fact.Memory, eviction: fact.AlwaysInMemory))
  Nil
}

import gleam/io
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import gclaw/memory
import gclaw/fact as gfact
import gleamdb/fact

pub fn main() {
  gleeunit.main()
}

// Helper to create a dummy vector
// Helper to create orthogonal vectors
fn vec_a() -> List(Float) {
  [1.0, ..list.repeat(0.0, 767)]
}

fn vec_b() -> List(Float) {
  [0.0, 1.0, ..list.repeat(0.0, 766)]
}

pub fn hybrid_retrieval_test() {
  let mem = memory.init_ephemeral()
  let session = "hybrid_sess"
  
  // 1. Assert Old Fact with Vector (simulating "Apple is a fruit")
  let eid1 = fact.deterministic_uid("old_fact")
  let vec1 = vec_a() // Strong vector
  let mem = memory.remember_semantic(mem, [
    #(eid1, gfact.msg_content, fact.Str("Apple is a fruit")),
    #(eid1, gfact.msg_role, fact.Str("user")),
    #(eid1, gfact.msg_session, fact.Str(session)),
    #(eid1, gfact.msg_timestamp, fact.Int(100))
  ], vec1)

  // 2. Assert Recent Fact (simulating "I like cars")
  let eid2 = fact.deterministic_uid("new_fact")
  let vec2 = vec_b() // Weak vector
  let mem = memory.remember_semantic(mem, [
    #(eid2, gfact.msg_content, fact.Str("I like cars")),
    #(eid2, gfact.msg_role, fact.Str("user")),
    #(eid2, gfact.msg_session, fact.Str(session)),
    #(eid2, gfact.msg_timestamp, fact.Int(200))
  ], vec2)

  // 3. Query: "Tell me about fruit" 
  // Limit is 1.
  
  let context = memory.get_context_window(mem, session, 1, vec_a())
  
  io.println("Context Result: " <> string.inspect(context))
  should.equal(list.length(context), 2)
  
  // Should contain BOTH if limit applies to each stream separately
  // Recent: "I like cars" (ts=200)
  // Semantic: "Apple is a fruit" (sim=1.0)
  
  list.contains(context, "user: Apple is a fruit") |> should.be_true
  list.contains(context, "user: I like cars") |> should.be_true
}

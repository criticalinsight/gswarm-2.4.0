import gleeunit/should
import gclaw/memory
import gclaw/fact as gfact
import gleamdb/fact
import gleam/list

pub fn context_retrieval_test() {
  let mem = memory.init_ephemeral()
  let ts1 = 1700000000
  let ts2 = 1700000010
  
  let msg1_eid = fact.deterministic_uid("sess_1_msg_1")
  let msg2_eid = fact.deterministic_uid("sess_1_msg_2")
  
  let facts = [
    #(msg1_eid, gfact.msg_content, fact.Str("First")),
    #(msg1_eid, gfact.msg_role, fact.Str("user")),
    #(msg1_eid, gfact.msg_session, fact.Str("sess_1")),
    #(msg1_eid, gfact.msg_timestamp, fact.Int(ts1)),
    
    #(msg2_eid, gfact.msg_content, fact.Str("Second")),
    #(msg2_eid, gfact.msg_role, fact.Str("assistant")),
    #(msg2_eid, gfact.msg_session, fact.Str("sess_1")),
    #(msg2_eid, gfact.msg_timestamp, fact.Int(ts2))
  ]
  
  let mem = memory.remember(mem, facts)
  
  // Retrieve context for sess_1
  let context = memory.get_context_window(mem, "sess_1", 10, [])
  
  list.length(context)
    |> should.equal(2)
  
  case context {
    [first, second] -> {
      first |> should.equal("user: First")
      second |> should.equal("assistant: Second")
    }
    _ -> panic as "Expected 2 context items"
  }
}

pub fn session_isolation_test() {
  let mem = memory.init_ephemeral()
  
  // Session A
  let eid_a = fact.deterministic_uid("msg_a")
  let facts_a = [
    #(eid_a, gfact.msg_content, fact.Str("A")),
    #(eid_a, gfact.msg_role, fact.Str("user")),
    #(eid_a, gfact.msg_session, fact.Str("sess_a")),
    #(eid_a, gfact.msg_timestamp, fact.Int(100))
  ]
  
  // Session B
  let eid_b = fact.deterministic_uid("msg_b")
  let facts_b = [
    #(eid_b, gfact.msg_content, fact.Str("B")),
    #(eid_b, gfact.msg_role, fact.Str("assistant")),
    #(eid_b, gfact.msg_session, fact.Str("sess_b")),
    #(eid_b, gfact.msg_timestamp, fact.Int(200))
  ]
  
  let mem = memory.remember(mem, list.flatten([facts_a, facts_b]))
  
  // Query Session A
  memory.get_context_window(mem, "sess_a", 10, [])
    |> should.equal(["user: A"])
    
  // Query Session B
  memory.get_context_window(mem, "sess_b", 10, [])
    |> should.equal(["assistant: B"])
}

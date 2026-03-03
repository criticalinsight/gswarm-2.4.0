import gleeunit/should
import gclaw/memory
import gclaw/fact as gfact
import gleamdb/fact
import simplifile

pub fn persistence_test() {
  let db_path = "test_persistence.db"
  let _ = simplifile.delete(db_path)
  
  // 1. Initial session: Assert facts
  {
    let mem = memory.init_persistent(db_path)
    let eid = fact.deterministic_uid("p_test")
    let _mem = memory.remember(mem, [
      #(eid, gfact.msg_content, fact.Str("Persistent Fact")),
      #(eid, gfact.msg_session, fact.Str("session_p")),
      #(eid, gfact.msg_role, fact.Str("user")),
      #(eid, gfact.msg_timestamp, fact.Int(500))
    ])
    // Destructor (close) isn't strictly needed for our disk adapter as it appends immediately
  }
  
  // 2. New session: Re-init and recall
  {
    let mem = memory.init_persistent(db_path)
    let context = memory.get_context_window(mem, "session_p", 10, [])
    
    context |> should.equal(["user: Persistent Fact"])
  }
  
  let _ = simplifile.delete(db_path)
}

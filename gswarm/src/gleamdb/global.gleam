import gleam/erlang/process.{type Pid}

@external(erlang, "gleamdb_global_ffi", "register")
pub fn register(name: String, pid: Pid) -> Result(Nil, Nil)

@external(erlang, "gleamdb_global_ffi", "whereis")
pub fn whereis(name: String) -> Result(Pid, Nil)

@external(erlang, "gleamdb_global_ffi", "unregister")
pub fn unregister(name: String) -> Nil

import gleam/erlang/process.{type Subject, type Pid}

@external(erlang, "gleamdb_process_ffi", "subject_to_pid")
pub fn subject_to_pid(subject: Subject(any)) -> Pid

@external(erlang, "gleamdb_process_ffi", "pid_to_subject")
pub fn pid_to_subject(pid: Pid) -> Subject(any)

@external(erlang, "gleamdb_process_ffi", "self")
pub fn self() -> Pid

@external(erlang, "gleamdb_process_ffi", "is_alive")
pub fn is_alive(subject: Subject(any)) -> Bool

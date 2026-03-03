-module(gleamdb_process_ffi).
-export([subject_to_pid/1, pid_to_subject/1, self/0, is_alive/1]).

subject_to_pid({subject, Pid, _Tag}) -> Pid.

pid_to_subject(Pid) -> {subject, Pid, make_ref()}.

self() -> erlang:self().

is_alive({subject, Pid, _Tag}) -> erlang:is_process_alive(Pid);
is_alive(Pid) when is_pid(Pid) -> erlang:is_process_alive(Pid);
is_alive(_) -> false.

-module(gleamdb_raft_ffi).
-export([start_election_timer/1, start_heartbeat_timer/1, cancel_timer/1, random_election_timeout/0]).

%% Send an ElectionTimeout message after a random delay (150-300ms).
%% Returns a timer reference that can be cancelled.
start_election_timer(Subject) ->
    Timeout = random_election_timeout(),
    erlang:send_after(Timeout, element(2, Subject), element(3, Subject)).

%% Send a HeartbeatTick message at a fixed interval (50ms).
%% Returns a timer reference that can be cancelled.
start_heartbeat_timer(Subject) ->
    erlang:send_after(50, element(2, Subject), element(3, Subject)).

%% Cancel a pending timer. Safe to call with any value.
cancel_timer(Ref) when is_reference(Ref) ->
    erlang:cancel_timer(Ref),
    nil;
cancel_timer(_) ->
    nil.

%% Random timeout between 150 and 300 milliseconds.
random_election_timeout() ->
    150 + rand:uniform(150).

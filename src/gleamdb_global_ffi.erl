-module(gleamdb_global_ffi).
-export([register/2, whereis/1, unregister/1]).

register(Name, Pid) ->
    case global:register_name(Name, Pid) of
        yes -> {ok, nil};
        no -> {error, nil}
    end.

whereis(Name) ->
    case global:whereis_name(Name) of
        undefined -> {error, nil};
        Pid -> {ok, Pid}
    end.

unregister(Name) ->
    global:unregister_name(Name),
    nil.

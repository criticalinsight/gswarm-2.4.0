-module(gswarm_ffi).
-export([get_env/1]).

get_env(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Val -> {ok, list_to_binary(Val)}
    end.

-module(gclaw_ffi).
-export([get_env/1, get_line/1]).

get_env(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Val -> {ok, unicode:characters_to_binary(Val)}
    end.

get_line(Prompt) ->
    case io:get_line(binary_to_list(Prompt)) of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Data -> {ok, unicode:characters_to_binary(Data)}
    end.

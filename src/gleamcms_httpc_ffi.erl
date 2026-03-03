-module(gleamcms_httpc_ffi).
-export([post/3, get_env/1, shell_exec/1]).

shell_exec(Command) ->
    case os:cmd(binary_to_list(Command)) of
        Output -> {ok, list_to_binary(Output)}
    end.

post(Url, Headers, Body) ->
    inets:start(),
    ssl:start(),
    UrlStr = binary_to_list(Url),
    HeadersList = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- Headers],
    BodyStr = binary_to_list(Body),
    ContentType = "application/json",
    
    case httpc:request(post, {UrlStr, HeadersList, ContentType, BodyStr}, [], []) of
        {ok, {{_Version, 200, _Reason}, _RespHeaders, RespBody}} ->
            {ok, list_to_binary(RespBody)};
        {ok, {{_Version, Status, Reason}, _RespHeaders, RespBody}} ->
            {error, list_to_binary(io_lib:format("HTTP ~p: ~s - ~s", [Status, Reason, RespBody]))};
        {error, Reason} ->
            {error, list_to_binary(io_lib:format("Network error: ~p", [Reason]))}
    end.

get_env(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Val -> {ok, list_to_binary(Val)}
    end.

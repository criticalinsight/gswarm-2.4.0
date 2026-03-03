-module(coverage_ffi).
-export([start/0, compile/1, analyze/1, stop/0]).

start() ->
    cover:start().

compile(Dir) ->
    Results = cover:compile_beam_directory(binary_to_list(Dir)),
    Modules = [M || {ok, M} <- Results],
    {ok, Modules}.

analyze(Modules) ->
    Results = lists:map(fun(M) ->
        case cover:analyze(M, coverage, line) of
            {ok, {M, Lines}} ->
                process_lines(M, Lines);
            {ok, Lines} when is_list(Lines) ->
                process_lines(M, Lines);
            _ -> {M, 0, 0}
        end
    end, Modules),
    Results.

process_lines(M, Lines) ->
    {Cov, NonCov} = lists:foldl(fun(LineData, {C, N}) ->
        case LineData of
            {{M, _}, Count} when Count == 0 -> {C, N + 1};
            {{M, _}, _Count} -> {C + 1, N};
            _ -> {C, N}
        end
    end, {0, 0}, Lines),
    {atom_to_binary(M, utf8), Cov, NonCov}.

stop() ->
    cover:stop().

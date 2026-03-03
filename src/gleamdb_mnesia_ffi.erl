-module(gleamdb_mnesia_ffi).
-export([init/0, persist/1, persist_batch/1, recover/0]).

init() ->
    case mnesia:system_info(is_running) of
        yes -> ok;
        _ -> 
            _ = mnesia:create_schema([node()]),
            application:ensure_all_started(mnesia)
    end,
    
    ExpectedAttrs = [entity, attribute, value, tx, tx_index, valid_time, operation],
    try mnesia:table_info(datoms, attributes) of
        ExpectedAttrs -> ok;
        _ -> 
            error_logger:info_msg("Schema mismatch for table 'datoms'. Deleting and recreating.~n"),
            mnesia:delete_table(datoms)
    catch
        exit:{aborted, _} -> ok % Table does not exist
    end,

    case mnesia:create_table(datoms, [
        {record_name, datom},
        {attributes, ExpectedAttrs},
        {disc_copies, [node()]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, datoms}} -> ok;
        _ -> ok
    end,
    mnesia:wait_for_tables([datoms], 5000),
    nil.

persist(Datom) ->
    mnesia:dirty_write(datoms, Datom),
    nil.

persist_batch(Datoms) ->
    F = fun() ->
        lists:foreach(fun(D) -> mnesia:write(datoms, D, write) end, Datoms)
    end,
    mnesia:transaction(F),
    nil.

recover() ->
    F = fun() ->
        mnesia:match_object(datoms, {datom, '_', '_', '_', '_', '_', '_', '_'}, read)
    end,
    case mnesia:transaction(F) of
        {atomic, Records} -> {ok, Records};
        {aborted, Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.

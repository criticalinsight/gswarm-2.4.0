-module(gleamdb_telemetry_ffi).
-export([system_time/0]).

system_time() ->
    erlang:system_time(millisecond).

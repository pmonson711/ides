-module(demo).
-behaviour(application).

-export([start/2, stop/1, whereis/1]).

start(_Type, _Args) ->
    case demo_sup:start_link() of
        {ok, Pid} ->
            supervisor:start_child(demo_db_pool, []),
            supervisor:start_child(demo_db_pool, []),
            {ok, Pid};
        Error ->
            Error
    end.

stop(_State) ->
    ok.

whereis(Name) ->
    case erlang:whereis(Name) of
        undefined -> {error, not_found};
        Pid when is_pid(Pid) -> {ok, Pid}
    end.

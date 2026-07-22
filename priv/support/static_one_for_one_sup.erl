-module(static_one_for_one_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 3,
        period => 10
    },
    Children = [
        #{
            id => worker_a,
            start => {static_worker, start_link, []},
            restart => permanent,
            type => worker,
            modules => [static_worker]
        },
        #{
            id => worker_b,
            start => {static_worker, start_link, []},
            restart => transient,
            type => worker,
            modules => [static_worker]
        }
    ],
    {ok, {SupFlags, Children}}.

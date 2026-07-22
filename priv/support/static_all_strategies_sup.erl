-module(static_all_strategies_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 5,
        period => 60
    },
    Children = [
        #{
            id => child_1,
            start => {static_worker, start_link, []},
            restart => permanent,
            type => worker,
            modules => [static_worker]
        },
        #{
            id => child_2,
            start => {static_worker, start_link, []},
            restart => transient,
            type => worker,
            modules => [static_worker]
        },
        #{
            id => child_3,
            start => {static_worker, start_link, []},
            restart => temporary,
            type => worker,
            modules => [static_worker]
        }
    ],
    {ok, {SupFlags, Children}}.

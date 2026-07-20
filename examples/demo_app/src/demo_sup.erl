-module(demo_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 1,
        period => 5
    },
    Children = [
        #{
            id => demo_db_pool,
            start => {demo_db_pool, start_link, []},
            restart => permanent,
            type => supervisor,
            modules => [demo_db_pool]
        },
        #{
            id => demo_web_sup,
            start => {demo_web_sup, start_link, []},
            restart => permanent,
            type => supervisor,
            modules => [demo_web_sup]
        },
        #{
            id => demo_cache,
            start => {demo_cache, start_link, []},
            restart => permanent,
            type => worker,
            modules => [demo_cache]
        },
        #{
            id => demo_metrics,
            start => {demo_metrics, start_link, []},
            restart => permanent,
            type => worker,
            modules => [demo_metrics]
        }
    ],
    {ok, {SupFlags, Children}}.

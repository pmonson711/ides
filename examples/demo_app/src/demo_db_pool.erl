-module(demo_db_pool).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 5,
        period => 5
    },
    ChildSpec = #{
        id => demo_db_worker,
        start => {demo_db_worker, start_link, []},
        restart => temporary,
        type => worker,
        modules => [demo_db_worker]
    },
    {ok, {SupFlags, [ChildSpec]}}.

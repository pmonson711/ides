-module(demo_web_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => rest_for_one,
        intensity => 1,
        period => 5
    },
    Children = [
        #{
            id => demo_router,
            start => {demo_router, start_link, []},
            restart => permanent,
            type => worker,
            modules => [demo_router]
        },
        #{
            id => demo_handler_sup,
            start => {demo_handler_sup, start_link, []},
            restart => permanent,
            type => supervisor,
            modules => [demo_handler_sup]
        }
    ],
    {ok, {SupFlags, Children}}.

-module(demo_handler_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 1,
        period => 5
    },
    Children = [
        #{
            id => demo_auth,
            start => {demo_auth, start_link, []},
            restart => permanent,
            type => worker,
            modules => [demo_auth]
        },
        #{
            id => demo_api,
            start => {demo_api, start_link, []},
            restart => permanent,
            type => worker,
            modules => [demo_api]
        },
        #{
            id => demo_logger,
            start => {demo_logger, start_link, []},
            restart => permanent,
            type => worker,
            modules => [demo_logger]
        }
    ],
    {ok, {SupFlags, Children}}.

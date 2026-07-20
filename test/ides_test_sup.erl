-module(ides_test_sup).

-behaviour(supervisor).

-export([start_link/3, init/1, start_child/0, child_init/1]).

start_link(Name, Strategy, Children) ->
    supervisor:start_link({local, Name}, ?MODULE, {Strategy, Children}).

init({Strategy, Children}) ->
    SupFlags = #{strategy => Strategy, intensity => 1, period => 5},
    {ok, {SupFlags, Children}}.

start_child() ->
    proc_lib:start_link(?MODULE, child_init, [self()]).

child_init(Parent) ->
    proc_lib:init_ack(Parent, {ok, self()}),
    timer:sleep(60000).

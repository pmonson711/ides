-module(demo_arch_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1
]).

-export([
    demo_sup_is_one_for_one_test/1,
    db_pool_is_simple_one_for_one_test/1,
    web_sup_is_rest_for_one_test/1,
    handler_sup_is_one_for_all_test/1,
    auth_ancestor_chain_test/1,
    cache_and_metrics_are_siblings_test/1,
    web_sup_children_order_test/1
]).

all() ->
    [
        demo_sup_is_one_for_one_test,
        db_pool_is_simple_one_for_one_test,
        web_sup_is_rest_for_one_test,
        handler_sup_is_one_for_all_test,
        auth_ancestor_chain_test,
        cache_and_metrics_are_siblings_test,
        web_sup_children_order_test
    ].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(demo),
    Config.

end_per_suite(_Config) ->
    application:stop(demo),
    ok.

%% --- Strategy tests ---

demo_sup_is_one_for_one_test(_Config) ->
    {ok, AuthPid} = demo:whereis(demo_auth),
    {ok, Tree} = ides:ancestors(AuthPid),
    ?assertEqual(one_for_one, maps:get(strategy, Tree)),
    ?assertEqual("demo_sup", maps:get(name, Tree)).

db_pool_is_simple_one_for_one_test(_Config) ->
    {ok, AuthPid} = demo:whereis(demo_auth),
    {ok, #{children := Children}} = ides:ancestors(AuthPid),
    Pool = find_child("demo_db_pool", Children),
    ?assertEqual(simple_one_for_one, maps:get(strategy, Pool)).

web_sup_is_rest_for_one_test(_Config) ->
    {ok, AuthPid} = demo:whereis(demo_auth),
    {ok, #{children := Children}} = ides:ancestors(AuthPid),
    WebSup = find_child("demo_web_sup", Children),
    ?assertEqual(rest_for_one, maps:get(strategy, WebSup)).

handler_sup_is_one_for_all_test(_Config) ->
    {ok, AuthPid} = demo:whereis(demo_auth),
    {ok, #{children := Children}} = ides:ancestors(AuthPid),
    WebSup = find_child("demo_web_sup", Children),
    HandlerSup = find_child("demo_handler_sup", maps:get(children, WebSup)),
    ?assertEqual(one_for_all, maps:get(strategy, HandlerSup)).

%% --- Ancestor chain test ---

auth_ancestor_chain_test(_Config) ->
    {ok, AuthPid} = demo:whereis(demo_auth),
    {ok, Tree} = ides:ancestors(AuthPid),
    %% demo_sup
    ?assertEqual("demo_sup", maps:get(name, Tree)),
    %% demo_sup -> web_sup
    WebSup = find_child("demo_web_sup", maps:get(children, Tree)),
    ?assertEqual("demo_web_sup", maps:get(name, WebSup)),
    %% web_sup -> handler_sup
    HandlerSup = find_child("demo_handler_sup", maps:get(children, WebSup)),
    ?assertEqual("demo_handler_sup", maps:get(name, HandlerSup)),
    %% handler_sup -> auth (target)
    Auth = find_child("demo_auth", maps:get(children, HandlerSup)),
    ?assertEqual(AuthPid, maps:get(pid, Auth)),
    ?assertEqual(worker, maps:get(type, Auth)),
    ?assertEqual(permanent, maps:get(restart_type, Auth)).

%% --- Sibling structure ---

cache_and_metrics_are_siblings_test(_Config) ->
    {ok, CachePid} = demo:whereis(demo_cache),
    {ok, #{children := Children}} = ides:ancestors(CachePid),
    Cache = find_child("demo_cache", Children),
    Metrics = find_child("demo_metrics", Children),
    ?assertEqual(CachePid, maps:get(pid, Cache)),
    ?assert(is_pid(maps:get(pid, Metrics))),
    ?assertEqual(permanent, maps:get(restart_type, Cache)),
    ?assertEqual(permanent, maps:get(restart_type, Metrics)).

%% --- Child ordering ---

web_sup_children_order_test(_Config) ->
    {ok, RouterPid} = demo:whereis(demo_router),
    {ok, #{children := Children}} = ides:ancestors(RouterPid),
    WebSup = find_child("demo_web_sup", Children),
    WebChildren = maps:get(children, WebSup),
    ?assertEqual(2, length(WebChildren)),
    [First, Second] = WebChildren,
    ?assertEqual("demo_handler_sup", maps:get(name, First)),
    ?assertEqual("demo_router", maps:get(name, Second)).

%% --- Helpers ---

find_child(Name, Children) ->
    case lists:filter(fun(#{name := N}) -> N =:= Name end, Children) of
        [Child] -> Child;
        [] -> error({child_not_found, Name})
    end.

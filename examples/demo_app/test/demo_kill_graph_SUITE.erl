-module(demo_kill_graph_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1
]).

-export([
    one_for_one_cache_isolated_from_metrics_test/1,
    one_for_one_metrics_isolated_from_cache_test/1,
    one_for_all_auth_includes_siblings_test/1,
    one_for_all_api_includes_siblings_test/1,
    one_for_all_logger_includes_siblings_test/1,
    rest_for_one_first_child_no_sibling_killers_test/1,
    rest_for_one_later_child_has_earlier_killers_test/1,
    every_process_includes_parent_supervisor_test/1
]).

all() ->
    [
        one_for_one_cache_isolated_from_metrics_test,
        one_for_one_metrics_isolated_from_cache_test,
        one_for_all_auth_includes_siblings_test,
        one_for_all_api_includes_siblings_test,
        one_for_all_logger_includes_siblings_test,
        rest_for_one_first_child_no_sibling_killers_test,
        rest_for_one_later_child_has_earlier_killers_test,
        every_process_includes_parent_supervisor_test
    ].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(demo),
    Config.

end_per_suite(_Config) ->
    application:stop(demo),
    ok.

%% --- one_for_one isolation ---
%% Under one_for_one, siblings do not kill each other.

one_for_one_cache_isolated_from_metrics_test(_Config) ->
    {ok, CachePid} = demo:whereis(demo_cache),
    {ok, MetricsPid} = demo:whereis(demo_metrics),
    {ok, Killers} = ides:kill_graph(CachePid),
    ?assertNot(lists:member(MetricsPid, Killers)).

one_for_one_metrics_isolated_from_cache_test(_Config) ->
    {ok, CachePid} = demo:whereis(demo_cache),
    {ok, MetricsPid} = demo:whereis(demo_metrics),
    {ok, Killers} = ides:kill_graph(MetricsPid),
    ?assertNot(lists:member(CachePid, Killers)).

%% --- one_for_all cascade ---
%% Under one_for_all, all siblings are killers for each other.

one_for_all_auth_includes_siblings_test(_Config) ->
    {ok, AuthPid} = demo:whereis(demo_auth),
    {ok, ApiPid} = demo:whereis(demo_api),
    {ok, LoggerPid} = demo:whereis(demo_logger),
    {ok, Killers} = ides:kill_graph(AuthPid),
    ?assert(lists:member(ApiPid, Killers)),
    ?assert(lists:member(LoggerPid, Killers)).

one_for_all_api_includes_siblings_test(_Config) ->
    {ok, AuthPid} = demo:whereis(demo_auth),
    {ok, ApiPid} = demo:whereis(demo_api),
    {ok, LoggerPid} = demo:whereis(demo_logger),
    {ok, Killers} = ides:kill_graph(ApiPid),
    ?assert(lists:member(AuthPid, Killers)),
    ?assert(lists:member(LoggerPid, Killers)).

one_for_all_logger_includes_siblings_test(_Config) ->
    {ok, AuthPid} = demo:whereis(demo_auth),
    {ok, ApiPid} = demo:whereis(demo_api),
    {ok, LoggerPid} = demo:whereis(demo_logger),
    {ok, Killers} = ides:kill_graph(LoggerPid),
    ?assert(lists:member(ApiPid, Killers)),
    ?assert(lists:member(AuthPid, Killers)).

%% --- rest_for_one ---
%% Under rest_for_one, siblings at earlier positions (in which_children order)
%% are killers for later children. The first child has no sibling killers.
%% Determined dynamically since which_children map-iteration order varies by OTP version.

rest_for_one_first_child_no_sibling_killers_test(_Config) ->
    [FirstPid, SecondPid | _] = web_sup_child_pids(),
    {ok, Killers} = ides:kill_graph(FirstPid),
    ?assertNot(lists:member(SecondPid, Killers)).

rest_for_one_later_child_has_earlier_killers_test(_Config) ->
    [FirstPid, SecondPid | _] = web_sup_child_pids(),
    {ok, Killers} = ides:kill_graph(SecondPid),
    ?assert(lists:member(FirstPid, Killers)).

%% --- Parent supervisor always in kill graph ---

every_process_includes_parent_supervisor_test(_Config) ->
    {ok, AuthPid} = demo:whereis(demo_auth),
    {ok, HandlerPid} = demo:whereis(demo_handler_sup),
    {ok, Killers} = ides:kill_graph(AuthPid),
    ?assert(lists:member(HandlerPid, Killers)).

%% --- Helpers ---

web_sup_child_pids() ->
    Children = supervisor:which_children(demo_web_sup),
    [Pid || {_Id, Pid, _Type, _Mods} <- Children, is_pid(Pid)].

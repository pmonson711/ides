-module(ides_static_tests).

-include_lib("eunit/include/eunit.hrl").

support_beams() ->
    Files = filelib:wildcard("priv/support/static_*.erl"),
    [begin
         Src = filename:rootname(F) ++ ".erl",
         {ok, _Mod, Beam} = compile:file(Src, [debug_info, binary, report, return_errors]),
         Beam
     end || F <- Files].

supervisor_tree_from_support_beams_test() ->
    Beams = support_beams(),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    ?assert(length(Tree) >= 2),
    SupModules = [maps:get(module, S) || S <- Tree],
    ?assert(lists:member(static_one_for_one_sup, SupModules)),
    ?assert(lists:member(static_all_strategies_sup, SupModules)).

supervisor_tree_specific_module_test() ->
    Beams = support_beams(),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    [Sup] = [S || S <- Tree, maps:get(module, S) =:= static_one_for_one_sup],
    ?assertEqual(one_for_one, maps:get(strategy, Sup)),
    Intensity = maps:get(intensity, Sup),
    ?assertEqual(3, maps:get(max_restarts, Intensity)),
    ?assertEqual(10, maps:get(max_period, Intensity)),
    Children = maps:get(children, Sup),
    ?assertEqual(2, length(Children)),
    [ChildA, ChildB] = Children,
    ?assertEqual("worker_a", maps:get(name, ChildA)),
    ?assertEqual(static_worker, maps:get(module, ChildA)),
    ?assertEqual(worker, maps:get(type, ChildA)),
    ?assertEqual(permanent, maps:get(restart_type, ChildA)),
    ?assertEqual("worker_b", maps:get(name, ChildB)).

intensity_info_test() ->
    Beams = support_beams(),
    {ok, Intensity} = ides_static:intensity_info(static_one_for_one_sup, Beams),
    ?assertEqual(3, maps:get(max_restarts, Intensity)),
    ?assertEqual(10, maps:get(max_period, Intensity)).

kill_graph_test() ->
    Beams = support_beams(),
    {ok, Killers} = ides_static:kill_graph(static_worker, Beams),
    ?assertEqual(2, length(Killers)),
    ?assert(lists:member(static_all_strategies_sup, Killers)),
    ?assert(lists:member(static_one_for_one_sup, Killers)).

ancestors_test() ->
    Beams = support_beams(),
    {ok, Ancestors} = ides_static:ancestors(static_worker, Beams),
    ?assertEqual(2, length(Ancestors)).

siblings_test() ->
    Beams = support_beams(),
    {ok, Siblings} = ides_static:siblings(static_worker, Beams),
    ?assert(is_list(Siblings)).

format_test() ->
    Beams = support_beams(),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    Output = lists:flatten(ides_static:format(static_worker, Tree)),
    ?assert(string:str(Output, "static_one_for_one_sup") > 0).

not_a_supervisor_error_test() ->
    Beams = support_beams(),
    ?assertMatch({error, {not_a_supervisor, _}},
                 ides_static:intensity_info(static_worker, Beams)).

missing_beam_warning_test() ->
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(["/nonexistent/path/to/beam"]),
    ?assertEqual([], Tree).

find_process_by_name_test() ->
    Beams = support_beams(),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    ?assertMatch({ok, static_one_for_one_sup},
                 ides_static:find_process_by_name("static_one_for_one_sup", Tree)).

find_process_by_name_not_found_test() ->
    Beams = support_beams(),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    ?assertMatch({error, not_found},
                 ides_static:find_process_by_name("nonexistent", Tree)).

%% --- Demo app integration tests ---

demo_app_beams() ->
    filelib:wildcard("examples/demo_app/_build/default/lib/demo/ebin/*.beam").

demo_supervisor_tree_test() ->
    Beams = demo_app_beams(),
    ?assert(length(Beams) > 0),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    [DemoSup] = [T || T <- Tree, maps:get(module, T) =:= demo_sup],
    ?assertEqual(one_for_one, maps:get(strategy, DemoSup)),
    Intensity = maps:get(intensity, DemoSup),
    ?assertEqual(1, maps:get(max_restarts, Intensity)),
    ?assertEqual(5, maps:get(max_period, Intensity)),
    Children = maps:get(children, DemoSup),
    ?assertEqual(4, length(Children)),
    ChildModules = [maps:get(module, C) || C <- Children],
    ?assert(lists:member(demo_db_pool, ChildModules)),
    ?assert(lists:member(demo_web_sup, ChildModules)),
    ?assert(lists:member(demo_cache, ChildModules)),
    ?assert(lists:member(demo_metrics, ChildModules)).

demo_web_sup_strategy_test() ->
    Beams = demo_app_beams(),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    [DemoSup] = [T || T <- Tree, maps:get(module, T) =:= demo_sup],
    [WebSup] = [C || C <- maps:get(children, DemoSup), maps:get(module, C) =:= demo_web_sup],
    ?assertEqual(rest_for_one, maps:get(strategy, WebSup)),
    WebChildren = maps:get(children, WebSup),
    ?assertEqual(2, length(WebChildren)),
    ChildMods = [maps:get(module, C) || C <- WebChildren],
    ?assert(lists:member(demo_router, ChildMods)),
    ?assert(lists:member(demo_handler_sup, ChildMods)).

demo_handler_sup_strategy_test() ->
    Beams = demo_app_beams(),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    [DemoSup] = [T || T <- Tree, maps:get(module, T) =:= demo_sup],
    [WebSup] = [C || C <- maps:get(children, DemoSup), maps:get(module, C) =:= demo_web_sup],
    [HandlerSup] = [C || C <- maps:get(children, WebSup), maps:get(module, C) =:= demo_handler_sup],
    ?assertEqual(one_for_all, maps:get(strategy, HandlerSup)),
    HandlerChildren = maps:get(children, HandlerSup),
    ?assertEqual(3, length(HandlerChildren)).

demo_db_pool_simple_one_for_one_test() ->
    Beams = demo_app_beams(),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    [DemoSup] = [T || T <- Tree, maps:get(module, T) =:= demo_sup],
    [DBPool] = [C || C <- maps:get(children, DemoSup), maps:get(module, C) =:= demo_db_pool],
    ?assertEqual(simple_one_for_one, maps:get(strategy, DBPool)).

demo_kill_graph_test() ->
    Beams = demo_app_beams(),
    {ok, Killers} = ides_static:kill_graph(demo_auth, Beams),
    ?assert(lists:member(demo_sup, Killers)),
    ?assert(lists:member(demo_web_sup, Killers)),
    ?assert(lists:member(demo_handler_sup, Killers)).

demo_ancestors_test() ->
    Beams = demo_app_beams(),
    {ok, Ancestors} = ides_static:ancestors(demo_auth, Beams),
    ?assertEqual([demo_sup, demo_web_sup, demo_handler_sup], Ancestors).

demo_ancestors_leaf_test() ->
    Beams = demo_app_beams(),
    {ok, Ancestors} = ides_static:ancestors(demo_cache, Beams),
    ?assertEqual([demo_sup], Ancestors).

demo_intensity_info_test() ->
    Beams = demo_app_beams(),
    {ok, Intensity} = ides_static:intensity_info(demo_db_pool, Beams),
    ?assertEqual(5, maps:get(max_restarts, Intensity)),
    ?assertEqual(5, maps:get(max_period, Intensity)).

demo_format_test() ->
    Beams = demo_app_beams(),
    {ok, #{tree := Tree}} = ides_static:supervisor_tree(Beams),
    Output = lists:flatten(ides_static:format(demo_auth, Tree)),
    ?assert(string:str(Output, "demo_sup") > 0),
    ?assert(string:str(Output, "demo_web_sup") > 0),
    ?assert(string:str(Output, "demo_handler_sup") > 0),
    ?assert(string:str(Output, "one_for_one") > 0),
    ?assert(string:str(Output, "rest_for_one") > 0),
    ?assert(string:str(Output, "one_for_all") > 0),
    ?assert(string:str(Output, "* demo_auth") > 0).

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

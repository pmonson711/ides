-module(ides_tests).

-include_lib("eunit/include/eunit.hrl").

smoke_test() ->
    ?assertEqual(1, 1).

exports_test() ->
    Expected = [
        {affected_siblings, 1},
        {ancestors, 1},
        {format, 2},
        {format_detail, 3},
        {format_init_analysis, 1},
        {init_analysis, 1},
        {kill_graph, 1},
        {kill_graph_detail, 1},
        {link_info, 1},
        {monitor_info, 1},
        {intensity_info, 1},
        {print, 2},
        {print_detail, 3},
        {print_init_analysis, 1},
        {should_restart, 2}
    ],
    Exports = [E || {Name, _} = E <- ides:module_info(exports), Name =/= module_info],
    ?assertEqual(
        lists:sort(Expected),
        lists:sort(Exports)
    ).

format_one_for_one_test() ->
    TargetPid = p2(),
    Tree = #{
        name => "my_sup",
        pid => p1(),
        type => supervisor,
        strategy => one_for_one,
        children => [
            #{name => "my_server", pid => p1(), type => worker, restart_type => permanent},
            #{name => "my_statem", pid => TargetPid, type => worker, restart_type => transient}
        ]
    },
    ?assertEqual(
        "my_sup (one_for_one, max 1/5s)\n"
        "    my_server (permanent)\n"
        "  * my_statem (transient)\n",
        lists:flatten(ides:format(TargetPid, Tree))
    ).

format_one_for_all_test() ->
    TargetPid = p2(),
    Tree = #{
        name => "my_sup",
        pid => p1(),
        type => supervisor,
        strategy => one_for_all,
        children => [
            #{name => "worker_1", pid => p1(), type => worker, restart_type => permanent},
            #{name => "worker_2", pid => TargetPid, type => worker, restart_type => permanent},
            #{name => "cache", pid => p3(), type => worker, restart_type => temporary}
        ]
    },
    ?assertEqual(
        "my_sup (one_for_all, max 1/5s)\n"
        "    worker_1 (permanent)\n"
        "  * worker_2 (permanent)\n"
        "    cache (temporary)\n",
        lists:flatten(ides:format(TargetPid, Tree))
    ).

format_rest_for_one_test() ->
    TargetPid = p2(),
    Tree = #{
        name => "my_sup",
        pid => p1(),
        type => supervisor,
        strategy => rest_for_one,
        children => [
            #{name => "startup", pid => p1(), type => worker, restart_type => permanent},
            #{name => "process", pid => TargetPid, type => worker, restart_type => permanent},
            #{name => "cleanup", pid => p3(), type => worker, restart_type => permanent}
        ]
    },
    ?assertEqual(
        "my_sup (rest_for_one, max 1/5s)\n"
        "    startup (permanent)\n"
        "  * process (permanent)\n"
        "    cleanup (permanent)\n",
        lists:flatten(ides:format(TargetPid, Tree))
    ).

format_simple_one_for_one_test() ->
    TargetPid = p2(),
    Tree = #{
        name => "pool_sup",
        pid => p1(),
        type => supervisor,
        strategy => simple_one_for_one,
        children => [
            #{name => "handler_1", pid => p1(), type => worker, restart_type => permanent},
            #{name => "handler_2", pid => TargetPid, type => worker, restart_type => permanent}
        ]
    },
    ?assertEqual(
        "pool_sup (simple_one_for_one, max 1/5s)\n"
        "    handler_1 (permanent)\n"
        "  * handler_2 (permanent)\n",
        lists:flatten(ides:format(TargetPid, Tree))
    ).

format_nested_test() ->
    TargetPid = p2(),
    Tree = #{
        name => "app_sup",
        pid => p1(),
        type => supervisor,
        strategy => one_for_one,
        children => [
            #{
                name => "sup1",
                pid => p3(),
                type => supervisor,
                strategy => one_for_all,
                restart_type => permanent,
                children => [
                    #{name => "worker_1", pid => p1(), type => worker, restart_type => permanent},
                    #{
                        name => "worker_2",
                        pid => TargetPid,
                        type => worker,
                        restart_type => permanent
                    }
                ]
            }
        ]
    },
    ?assertEqual(
        "app_sup (one_for_one, max 1/5s)\n"
        "    sup1 (one_for_all, permanent, max 1/5s)\n"
        "        worker_1 (permanent)\n"
        "      * worker_2 (permanent)\n",
        lists:flatten(ides:format(TargetPid, Tree))
    ).

format_returns_iolist_test() ->
    Target = spawn(fun() -> ok end),
    Tree = #{
        name => "s",
        pid => spawn(fun() -> ok end),
        type => supervisor,
        strategy => one_for_one,
        children => []
    },
    IoList = ides:format(Target, Tree),
    ?assert(is_list(IoList) orelse is_binary(IoList)),
    ?assert(is_list(lists:flatten(IoList))).

ancestors_no_proc_lib_test() ->
    Pid = spawn(fun() -> timer:sleep(1000) end),
    ?assertMatch({error, _}, ides:ancestors(Pid)),
    exit(Pid, kill).

ancestors_dead_process_test() ->
    Pid = spawn(fun() -> ok end),
    timer:sleep(10),
    ?assertMatch({error, _}, ides:ancestors(Pid)).

ancestors_one_for_one_integration_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => worker_a,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                },
                #{
                    id => worker_b,
                    start => {ides_test_sup, start_child, []},
                    restart => transient,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_o4o, one_for_one, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) ->
            exit(SupPid, shutdown)
        end,
        fun(SupPid) ->
            ?_test(begin
                [Child] = lists:filter(
                    fun({Id, _, _, _}) -> Id =:= worker_b end,
                    supervisor:which_children(SupPid)
                ),
                {_Id, WorkerBPid, _Type, _Mods} = Child,
                true = is_pid(WorkerBPid),
                {ok, Tree} = ides:ancestors(WorkerBPid),
                Output = lists:flatten(ides:format(WorkerBPid, Tree)),
                [SupLine | _] = string:split(string:trim(Output, trailing), "\n", all),
                ?assert(string:find(SupLine, "one_for_one") =/= nomatch),
                TargetLines = [
                    L
                 || L <- string:split(Output, "\n", all),
                    string:prefix(L, "  * ") =/= nomatch
                ],
                ?assertEqual(1, length(TargetLines))
            end)
        end}.

%% --- TLA+ property tests ---

should_restart_integration_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => perm_child,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                },
                #{
                    id => trans_child,
                    start => {ides_test_sup, start_child, []},
                    restart => transient,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                },
                #{
                    id => temp_child,
                    start => {ides_test_sup, start_child, []},
                    restart => temporary,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_sr, one_for_one, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) -> exit(SupPid, shutdown) end, fun(SupPid) ->
            ?_test(begin
                ChildList = supervisor:which_children(SupPid),
                {perm_child, P1, _, _} = lists:keyfind(perm_child, 1, ChildList),
                {trans_child, P2, _, _} = lists:keyfind(trans_child, 1, ChildList),
                {temp_child, P3, _, _} = lists:keyfind(temp_child, 1, ChildList),
                ?assert(ides:should_restart(P1, normal)),
                ?assert(ides:should_restart(P1, abnormal)),
                ?assertNot(ides:should_restart(P2, normal)),
                ?assert(ides:should_restart(P2, abnormal)),
                ?assertNot(ides:should_restart(P3, normal)),
                ?assertNot(ides:should_restart(P3, abnormal))
            end)
        end}.

kill_graph_integration_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => child_a,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                },
                #{
                    id => child_b,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_kg, one_for_one, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) -> exit(SupPid, shutdown) end, fun(SupPid) ->
            ?_test(begin
                ChildList1 = supervisor:which_children(SupPid),
                {child_a, P1, _, _} = lists:keyfind(child_a, 1, ChildList1),
                {child_b, P2, _, _} = lists:keyfind(child_b, 1, ChildList1),
                %% one_for_one: no sibling killers, only ancestors
                {ok, KG1} = ides:kill_graph(P1),
                ?assertNot(lists:member(P2, KG1)),
                ?assert(lists:member(SupPid, KG1)),
                exit(SupPid, shutdown)
            end)
        end}.

kill_graph_one_for_all_integration_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => child_x,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                },
                #{
                    id => child_y,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_kga, one_for_all, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) -> exit(SupPid, shutdown) end, fun(SupPid) ->
            ?_test(begin
                ChildList2 = supervisor:which_children(SupPid),
                {child_x, PX, _, _} = lists:keyfind(child_x, 1, ChildList2),
                {child_y, PY, _, _} = lists:keyfind(child_y, 1, ChildList2),
                %% one_for_all: all siblings are killers
                {ok, KG} = ides:kill_graph(PX),
                ?assert(lists:member(PY, KG)),
                ?assert(lists:member(SupPid, KG))
            end)
        end}.

affected_siblings_integration_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => child1,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                },
                #{
                    id => child2,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_as, one_for_one, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) -> exit(SupPid, shutdown) end, fun(SupPid) ->
            ?_test(begin
                ChildList = supervisor:which_children(SupPid),
                {child1, P1, _, _} = lists:keyfind(child1, 1, ChildList),
                {child2, P2, _, _} = lists:keyfind(child2, 1, ChildList),
                %% one_for_one: only the terminated child itself is affected
                {ok, Aff1} = ides:affected_siblings(P1),
                ?assertEqual(1, length(Aff1)),
                ?assert(lists:member(P1, Aff1)),
                ?assertNot(lists:member(P2, Aff1))
            end)
        end}.

affected_siblings_one_for_all_integration_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => child_a,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                },
                #{
                    id => child_b,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_as2, one_for_all, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) -> exit(SupPid, shutdown) end, fun(SupPid) ->
            ?_test(begin
                ChildList = supervisor:which_children(SupPid),
                {child_a, PA, _, _} = lists:keyfind(child_a, 1, ChildList),
                {child_b, PB, _, _} = lists:keyfind(child_b, 1, ChildList),
                %% one_for_all: all siblings are affected
                {ok, Aff} = ides:affected_siblings(PA),
                ?assertEqual(2, length(Aff)),
                ?assert(lists:member(PA, Aff)),
                ?assert(lists:member(PB, Aff))
            end)
        end}.

%% --- Link and monitor tests ---

link_info_alive_self_test() ->
    {ok, #{links := Links, traps_exits := Traps}} = ides:link_info(self()),
    ?assert(is_list(Links)),
    ?assertNot(lists:member(self(), Links)),
    ?assert(is_boolean(Traps)).

link_info_dead_process_test() ->
    Pid = spawn(fun() -> ok end),
    timer:sleep(10),
    ?assertMatch({error, _}, ides:link_info(Pid)).

monitor_info_alive_self_test() ->
    {ok, #{monitors := Monitors, monitored_by := MonitoredBy}} = ides:monitor_info(self()),
    ?assert(is_list(Monitors)),
    ?assert(is_list(MonitoredBy)).

monitor_info_dead_process_test() ->
    Pid = spawn(fun() -> ok end),
    timer:sleep(10),
    ?assertMatch({error, _}, ides:monitor_info(Pid)).

kill_graph_detail_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => child1,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_kgd, one_for_one, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) -> exit(SupPid, shutdown) end, fun(SupPid) ->
            ?_test(begin
                ChildList = supervisor:which_children(SupPid),
                {child1, ChildPid, _, _} = lists:keyfind(child1, 1, ChildList),
                {ok, Sources} = ides:kill_graph_detail(ChildPid),
                ?assert(is_list(Sources)),
                HasAncestor = lists:any(fun({ancestor, P}) -> P =:= SupPid end, Sources),
                ?assert(HasAncestor)
            end)
        end}.

kill_graph_includes_links_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => child_a,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_kgl, one_for_one, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) -> exit(SupPid, shutdown) end, fun(SupPid) ->
            ?_test(begin
                ChildList = supervisor:which_children(SupPid),
                {child_a, ChildPid, _, _} = lists:keyfind(child_a, 1, ChildList),
                {ok, KG} = ides:kill_graph(ChildPid),
                ?assert(lists:member(SupPid, KG)),
                {ok, #{links := Links, traps_exits := Traps}} = ides:link_info(ChildPid),
                ?assert(is_list(Links)),
                ?assert(is_boolean(Traps))
            end)
        end}.

%% --- Intensity info tests ---

intensity_info_integration_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => worker_a,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_ii, one_for_one, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) -> exit(SupPid, shutdown) end, fun(SupPid) ->
            ?_test(begin
                {ok, Info} = ides:intensity_info(SupPid),
                ?assert(is_map_key(max_restarts, Info)),
                ?assert(is_map_key(max_period, Info)),
                ?assert(is_integer(maps:get(max_restarts, Info))),
                ?assert(is_integer(maps:get(max_period, Info)))
            end)
        end}.

intensity_info_dead_process_test() ->
    Pid = spawn(fun() -> ok end),
    timer:sleep(10),
    {ok, Info} = ides:intensity_info(Pid),
    ?assertEqual(1, maps:get(max_restarts, Info)),
    ?assertEqual(5, maps:get(max_period, Info)).

init_analysis_format_test() ->
    TargetPid = spawn(fun() -> ok end),
    SupPid = spawn(fun() -> ok end),
    Result = #{
        supervisor => SupPid,
        sup_strategy => one_for_one,
        sup_intensity => #{max_restarts => 3, max_period => 5, current_count => 1, remaining => 2},
        target_pid => TargetPid,
        total_children => 4,
        worst_case_restarts => 3,
        remaining_budget => 2,
        children => [
            #{
                id => worker_a,
                pid => spawn(fun() -> ok end),
                restart_type => permanent,
                shutdown => 5000,
                phase => running,
                counts_against_intensity => true
            },
            #{
                id => worker_b,
                pid => spawn(fun() -> ok end),
                restart_type => transient,
                shutdown => 5000,
                phase => running,
                counts_against_intensity => true
            },
            #{
                id => worker_c,
                pid => TargetPid,
                restart_type => transient,
                shutdown => infinity,
                phase => running,
                counts_against_intensity => true
            },
            #{
                id => worker_d,
                pid => spawn(fun() -> ok end),
                restart_type => temporary,
                shutdown => 5000,
                phase => running,
                counts_against_intensity => false
            }
        ]
    },
    Output = lists:flatten(ides:format_init_analysis(Result)),
    Lines = string:split(string:trim(Output, trailing, "\n"), "\n", all),

    %% Header line: supervisor pid, strategy, intensity policy
    Line1 = lists:nth(1, Lines),
    ?assert(string:find(Line1, "Supervisor: <") =/= nomatch),
    ?assert(string:find(Line1, "one_for_one") =/= nomatch),
    ?assert(string:find(Line1, "max 3/5s") =/= nomatch),

    %% Summary counts (positional)
    ?assertEqual("Total children: 4", lists:nth(2, Lines)),
    ?assertEqual("Worst-case restart count: 3", lists:nth(3, Lines)),

    %% Section header (offset by blank line from format output)
    ?assertEqual("Children:", lists:nth(5, Lines)),

    %% Child entries: order-insensitive, just assert they exist with correct content
    ChildLines = lists:sublist(Lines, 6, 4),
    has_child(ChildLines, "* worker_c", "(transient, shutdown=infinity)"),
    has_child(ChildLines, "  worker_a", "(permanent, shutdown=5000)"),
    has_child(ChildLines, "  worker_b", "(transient, shutdown=5000)"),
    has_child(ChildLines, "  worker_d", "(temporary, shutdown=5000)    never restarted"),

    %% Footer is the last line
    Footer = lists:last(Lines),
    ?assert(string:find(Footer, "Remaining budget: 2") =/= nomatch),
    ?assert(string:find(Footer, "Worst case: 3") =/= nomatch),
    ?assert(string:find(Footer, "WARNING") =/= nomatch).

has_child(Lines, Marker, Anno) ->
    true = lists:any(
        fun(Line) ->
            string:find(Line, Marker) =/= nomatch andalso
                string:find(Line, Anno) =/= nomatch
        end,
        Lines
    ).

init_analysis_format_no_children_test() ->
    SupPid = spawn(fun() -> ok end),
    TargetPid = spawn(fun() -> ok end),
    Result = #{
        supervisor => SupPid,
        sup_strategy => one_for_one,
        sup_intensity => #{max_restarts => 1, max_period => 5},
        target_pid => TargetPid,
        total_children => 0,
        worst_case_restarts => 0,
        remaining_budget => 1,
        children => []
    },
    Output = lists:flatten(ides:format_init_analysis(Result)),
    Lines = string:split(string:trim(Output, trailing, "\n"), "\n", all),

    ?assertEqual("Total children: 0", lists:nth(2, Lines)),
    ?assertEqual("Worst-case restart count: 0", lists:nth(3, Lines)),

    %% No warning when within budget
    Footer = lists:last(Lines),
    ?assert(string:find(Footer, "Remaining budget: 1") =/= nomatch),
    ?assert(string:find(Footer, "Worst case: 0") =/= nomatch),
    ?assert(string:find(Footer, "WARNING") =:= nomatch).

init_analysis_integration_test_() ->
    {setup,
        fun() ->
            Children = [
                #{
                    id => perm_a,
                    start => {ides_test_sup, start_child, []},
                    restart => permanent,
                    shutdown => 5000,
                    type => worker,
                    modules => [ides_test_sup]
                },
                #{
                    id => trans_b,
                    start => {ides_test_sup, start_child, []},
                    restart => transient,
                    shutdown => infinity,
                    type => worker,
                    modules => [ides_test_sup]
                },
                #{
                    id => temp_c,
                    start => {ides_test_sup, start_child, []},
                    restart => temporary,
                    shutdown => 10000,
                    type => worker,
                    modules => [ides_test_sup]
                }
            ],
            {ok, SupPid} = ides_test_sup:start_link(test_ia, one_for_one, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) -> exit(SupPid, shutdown) end, fun(SupPid) ->
            ?_test(begin
                ChildList = supervisor:which_children(SupPid),
                {perm_a, PermPid, _, _} = lists:keyfind(perm_a, 1, ChildList),
                {ok, Analysis} = ides:init_analysis(PermPid),
                ?assertEqual(SupPid, maps:get(supervisor, Analysis)),
                ?assertEqual(one_for_one, maps:get(sup_strategy, Analysis)),
                ?assertEqual(3, maps:get(total_children, Analysis)),
                ?assertEqual(2, maps:get(worst_case_restarts, Analysis)),
                Children = maps:get(children, Analysis),
                ?assertEqual(3, length(Children)),
                PermInfo = find_child(perm_a, Children),
                ?assertEqual(true, maps:get(counts_against_intensity, PermInfo)),
                ?assertEqual(permanent, maps:get(restart_type, PermInfo)),
                ?assertEqual(5000, maps:get(shutdown, PermInfo)),
                TransInfo = find_child(trans_b, Children),
                ?assertEqual(true, maps:get(counts_against_intensity, TransInfo)),
                ?assertEqual(infinity, maps:get(shutdown, TransInfo)),
                TempInfo = find_child(temp_c, Children),
                ?assertEqual(false, maps:get(counts_against_intensity, TempInfo)),
                ?assertEqual(10000, maps:get(shutdown, TempInfo))
            end)
        end}.

find_child(Id, [#{id := Id} = Child | _]) -> Child;
find_child(Id, [_ | Rest]) -> find_child(Id, Rest).

%% helpers: throwaway PIDs for tree construction
p1() -> spawn(fun() -> ok end).
p2() -> spawn(fun() -> ok end).
p3() -> spawn(fun() -> ok end).

-module(ides_tests).

-include_lib("eunit/include/eunit.hrl").

smoke_test() ->
    ?assertEqual(1, 1).

exports_test() ->
    Expected = [{affected_siblings,1}, {ancestors,1}, {format,2}, {kill_graph,1}, {print,2}, {should_restart,2}],
    Exports = [E || {Name,_}=E <- ides:module_info(exports), Name =/= module_info],
    ?assertEqual(lists:sort(Expected),
                 lists:sort(Exports)).

format_one_for_one_test() ->
    TargetPid = p2(),
    Tree = #{name => "my_sup", pid => p1(), type => supervisor,
             strategy => one_for_one,
             children => [
                 #{name => "my_server", pid => p1(), type => worker, restart_type => permanent},
                 #{name => "my_statem", pid => TargetPid, type => worker, restart_type => transient}
             ]},
    ?assertEqual(
        "my_sup (one_for_one)\n"
        "    my_server (permanent)\n"
        "  * my_statem (transient)\n",
        lists:flatten(ides:format(TargetPid, Tree))).

format_one_for_all_test() ->
    TargetPid = p2(),
    Tree = #{name => "my_sup", pid => p1(), type => supervisor,
             strategy => one_for_all,
             children => [
                 #{name => "worker_1", pid => p1(), type => worker, restart_type => permanent},
                 #{name => "worker_2", pid => TargetPid, type => worker, restart_type => permanent},
                 #{name => "cache", pid => p3(), type => worker, restart_type => temporary}
             ]},
    ?assertEqual(
        "my_sup (one_for_all)\n"
        "    worker_1 (permanent)\n"
        "  * worker_2 (permanent)\n"
        "    cache (temporary)\n",
        lists:flatten(ides:format(TargetPid, Tree))).

format_rest_for_one_test() ->
    TargetPid = p2(),
    Tree = #{name => "my_sup", pid => p1(), type => supervisor,
             strategy => rest_for_one,
             children => [
                 #{name => "startup", pid => p1(), type => worker, restart_type => permanent},
                 #{name => "process", pid => TargetPid, type => worker, restart_type => permanent},
                 #{name => "cleanup", pid => p3(), type => worker, restart_type => permanent}
             ]},
    ?assertEqual(
        "my_sup (rest_for_one)\n"
        "    startup (permanent)\n"
        "  * process (permanent)\n"
        "    cleanup (permanent)\n",
        lists:flatten(ides:format(TargetPid, Tree))).

format_simple_one_for_one_test() ->
    TargetPid = p2(),
    Tree = #{name => "pool_sup", pid => p1(), type => supervisor,
             strategy => simple_one_for_one,
             children => [
                 #{name => "handler_1", pid => p1(), type => worker, restart_type => permanent},
                 #{name => "handler_2", pid => TargetPid, type => worker, restart_type => permanent}
             ]},
    ?assertEqual(
        "pool_sup (simple_one_for_one)\n"
        "    handler_1 (permanent)\n"
        "  * handler_2 (permanent)\n",
        lists:flatten(ides:format(TargetPid, Tree))).

format_nested_test() ->
    TargetPid = p2(),
    Tree = #{name => "app_sup", pid => p1(), type => supervisor,
             strategy => one_for_one,
             children => [
                 #{name => "sup1", pid => p3(), type => supervisor,
                   strategy => one_for_all, restart_type => permanent,
                   children => [
                       #{name => "worker_1", pid => p1(), type => worker, restart_type => permanent},
                       #{name => "worker_2", pid => TargetPid, type => worker, restart_type => permanent}
                   ]}
             ]},
    ?assertEqual(
        "app_sup (one_for_one)\n"
        "    sup1 (one_for_all, permanent)\n"
        "        worker_1 (permanent)\n"
        "      * worker_2 (permanent)\n",
        lists:flatten(ides:format(TargetPid, Tree))).

format_returns_iolist_test() ->
    Target = spawn(fun() -> ok end),
    Tree = #{name => "s", pid => spawn(fun() -> ok end), type => supervisor,
             strategy => one_for_one, children => []},
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
             #{id => worker_a,
               start => {ides_test_sup, start_child, []},
               restart => permanent,
               shutdown => 5000,
               type => worker,
               modules => [ides_test_sup]},
             #{id => worker_b,
               start => {ides_test_sup, start_child, []},
               restart => transient,
               shutdown => 5000,
               type => worker,
               modules => [ides_test_sup]}
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
                 supervisor:which_children(SupPid)),
             {_Id, WorkerBPid, _Type, _Mods} = Child,
             true = is_pid(WorkerBPid),
             {ok, Tree} = ides:ancestors(WorkerBPid),
             Output = lists:flatten(ides:format(WorkerBPid, Tree)),
             [SupLine | _] = string:split(string:trim(Output, trailing), "\n", all),
             ?assert(string:find(SupLine, "one_for_one") =/= nomatch),
             TargetLines = [L || L <- string:split(Output, "\n", all),
                                 string:prefix(L, "  * ") =/= nomatch],
             ?assertEqual(1, length(TargetLines))
         end)
     end}.

%% --- TLA+ property tests ---

should_restart_integration_test_() ->
    {setup,
     fun() ->
         Children = [
             #{id => perm_child, start => {ides_test_sup, start_child, []},
               restart => permanent, shutdown => 5000, type => worker, modules => [ides_test_sup]},
             #{id => trans_child, start => {ides_test_sup, start_child, []},
               restart => transient, shutdown => 5000, type => worker, modules => [ides_test_sup]},
             #{id => temp_child, start => {ides_test_sup, start_child, []},
               restart => temporary, shutdown => 5000, type => worker, modules => [ides_test_sup]}
         ],
         {ok, SupPid} = ides_test_sup:start_link(test_sr, one_for_one, Children),
         unlink(SupPid),
         SupPid
     end,
     fun(SupPid) -> exit(SupPid, shutdown) end,
     fun(SupPid) ->
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
             #{id => child_a, start => {ides_test_sup, start_child, []},
               restart => permanent, shutdown => 5000, type => worker, modules => [ides_test_sup]},
             #{id => child_b, start => {ides_test_sup, start_child, []},
               restart => permanent, shutdown => 5000, type => worker, modules => [ides_test_sup]}
         ],
         {ok, SupPid} = ides_test_sup:start_link(test_kg, one_for_one, Children),
         unlink(SupPid),
         SupPid
     end,
     fun(SupPid) -> exit(SupPid, shutdown) end,
     fun(SupPid) ->
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
             #{id => child_x, start => {ides_test_sup, start_child, []},
               restart => permanent, shutdown => 5000, type => worker, modules => [ides_test_sup]},
             #{id => child_y, start => {ides_test_sup, start_child, []},
               restart => permanent, shutdown => 5000, type => worker, modules => [ides_test_sup]}
         ],
         {ok, SupPid} = ides_test_sup:start_link(test_kga, one_for_all, Children),
         unlink(SupPid),
         SupPid
     end,
     fun(SupPid) -> exit(SupPid, shutdown) end,
     fun(SupPid) ->
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
             #{id => child1, start => {ides_test_sup, start_child, []},
               restart => permanent, shutdown => 5000, type => worker, modules => [ides_test_sup]},
             #{id => child2, start => {ides_test_sup, start_child, []},
               restart => permanent, shutdown => 5000, type => worker, modules => [ides_test_sup]}
         ],
         {ok, SupPid} = ides_test_sup:start_link(test_as, one_for_one, Children),
         unlink(SupPid),
         SupPid
     end,
     fun(SupPid) -> exit(SupPid, shutdown) end,
     fun(SupPid) ->
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
             #{id => child_a, start => {ides_test_sup, start_child, []},
               restart => permanent, shutdown => 5000, type => worker, modules => [ides_test_sup]},
             #{id => child_b, start => {ides_test_sup, start_child, []},
               restart => permanent, shutdown => 5000, type => worker, modules => [ides_test_sup]}
         ],
         {ok, SupPid} = ides_test_sup:start_link(test_as2, one_for_all, Children),
         unlink(SupPid),
         SupPid
     end,
     fun(SupPid) -> exit(SupPid, shutdown) end,
     fun(SupPid) ->
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

%% helpers: throwaway PIDs for tree construction
p1() -> spawn(fun() -> ok end).
p2() -> spawn(fun() -> ok end).
p3() -> spawn(fun() -> ok end).

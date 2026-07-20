-module(ides_tests).

-include_lib("eunit/include/eunit.hrl").

smoke_test() ->
    ?assertEqual(1, 1).

exports_test() ->
    Expected = [{ancestors,1}, {format,2}, {print,2}],
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

%% helpers: throwaway PIDs for tree construction
p1() -> spawn(fun() -> ok end).
p2() -> spawn(fun() -> ok end).
p3() -> spawn(fun() -> ok end).

-module(ides_prettypr_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test that prettypr output matches existing printer for one_for_one
format_one_for_one_matches_printer_test() ->
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
    Expected = lists:flatten(ides_printer:format(TargetPid, Tree)),
    Actual = lists:flatten(ides_prettypr:format(TargetPid, Tree)),
    ?assertEqual(Expected, Actual).

%% Test that prettypr output matches existing printer for one_for_all
format_one_for_all_matches_printer_test() ->
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
    Expected = lists:flatten(ides_printer:format(TargetPid, Tree)),
    Actual = lists:flatten(ides_prettypr:format(TargetPid, Tree)),
    ?assertEqual(Expected, Actual).

%% Test that prettypr output matches existing printer for nested supervisors
format_nested_matches_printer_test() ->
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
    Expected = lists:flatten(ides_printer:format(TargetPid, Tree)),
    Actual = lists:flatten(ides_prettypr:format(TargetPid, Tree)),
    ?assertEqual(Expected, Actual).

%% Test that format returns an iolist
format_returns_iolist_test() ->
    Target = spawn(fun() -> ok end),
    Tree = #{
        name => "s",
        pid => spawn(fun() -> ok end),
        type => supervisor,
        strategy => one_for_one,
        children => []
    },
    IoList = ides_prettypr:format(Target, Tree),
    ?assert(is_list(IoList) orelse is_binary(IoList)),
    ?assert(is_list(lists:flatten(IoList))).

%% helpers: throwaway PIDs for tree construction
p1() -> spawn(fun() -> ok end).
p2() -> spawn(fun() -> ok end).
p3() -> spawn(fun() -> ok end).

-module(ides_topology_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- one_for_one ---
one_for_one_topology_test_() ->
    Children = [
        #{
            id => my_server,
            start => {ides_test_sup, start_child, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [ides_test_sup]
        },
        #{
            id => my_statem,
            start => {ides_test_sup, start_child, []},
            restart => transient,
            shutdown => 5000,
            type => worker,
            modules => [ides_test_sup]
        }
    ],
    run_topology(test_o4o, one_for_one, Children, my_statem, [
        fun(Output) ->
            ?assert(string:find(Output, "one_for_one") =/= nomatch)
        end,
        fun(Output) ->
            ?assert(string:find(Output, "permanent") =/= nomatch)
        end,
        fun(Output) ->
            ?assert(string:find(Output, "transient") =/= nomatch)
        end,
        fun(Output) ->
            assert_target_line_contains("transient", Output)
        end,
        fun(Output) ->
            assert_line_count(3, Output)
        end
    ]).

%% --- one_for_all ---
one_for_all_topology_test_() ->
    Children = [
        #{
            id => worker_1,
            start => {ides_test_sup, start_child, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [ides_test_sup]
        },
        #{
            id => worker_2,
            start => {ides_test_sup, start_child, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [ides_test_sup]
        },
        #{
            id => cache,
            start => {ides_test_sup, start_child, []},
            restart => temporary,
            shutdown => 5000,
            type => worker,
            modules => [ides_test_sup]
        }
    ],
    run_topology(test_o4a, one_for_all, Children, worker_2, [
        fun(Output) ->
            ?assert(string:find(Output, "one_for_all") =/= nomatch)
        end,
        fun(Output) ->
            ?assert(string:find(Output, "temporary") =/= nomatch)
        end,
        fun(Output) ->
            assert_target_line_contains("permanent", Output)
        end,
        fun(Output) ->
            assert_line_count(4, Output)
        end
    ]).

%% --- rest_for_one ---
rest_for_one_topology_test_() ->
    Children = [
        #{
            id => startup,
            start => {ides_test_sup, start_child, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [ides_test_sup]
        },
        #{
            id => process,
            start => {ides_test_sup, start_child, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [ides_test_sup]
        },
        #{
            id => cleanup,
            start => {ides_test_sup, start_child, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [ides_test_sup]
        }
    ],
    run_topology(test_r4o, rest_for_one, Children, process, [
        fun(Output) ->
            ?assert(string:find(Output, "rest_for_one") =/= nomatch)
        end,
        fun(Output) ->
            assert_line_count(4, Output)
        end
    ]).

%% --- simple_one_for_one ---
simple_one_for_one_topology_test_() ->
    ChildTemplate = #{
        id => handler,
        start => {ides_test_sup, start_child, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [ides_test_sup]
    },
    {setup,
        fun() ->
            {ok, SupPid} = ides_test_sup:start_link(test_s4o, simple_one_for_one, [ChildTemplate]),
            unlink(SupPid),
            {ok, _} = supervisor:start_child(test_s4o, []),
            {ok, _} = supervisor:start_child(test_s4o, []),
            SupPid
        end,
        fun(SupPid) ->
            exit(SupPid, shutdown)
        end,
        fun(SupPid) ->
            ?_test(assert_simple_one_for_one_output(SupPid))
        end}.

%% --- helpers ---

run_topology(Name, Strategy, Children, TargetId, Checks) ->
    {setup,
        fun() ->
            {ok, SupPid} = ides_test_sup:start_link(Name, Strategy, Children),
            unlink(SupPid),
            SupPid
        end,
        fun(SupPid) ->
            exit(SupPid, shutdown)
        end,
        fun(SupPid) ->
            ?_test(run_topology_test(SupPid, TargetId, Checks))
        end}.

%% --- internal helpers ---

assert_simple_one_for_one_output(SupPid) ->
    Children = supervisor:which_children(SupPid),
    ?assertEqual(2, length(Children)),
    [_Child1, Child2] = Children,
    {_Id, TargetPid, _Type, _Mods} = Child2,
    true = is_pid(TargetPid),
    {ok, Tree} = ides:ancestors(TargetPid),
    Output = lists:flatten(ides:format(TargetPid, Tree)),
    ?assert(string:find(Output, "simple_one_for_one") =/= nomatch),
    TargetLines = [
        L
     || L <- string:split(Output, "\n", all),
        string:prefix(L, "  * ") =/= nomatch
    ],
    ?assertEqual(1, length(TargetLines)).

run_topology_test(SupPid, TargetId, Checks) ->
    [Child] = lists:filter(
        fun({Id, _, _, _}) -> Id =:= TargetId end,
        supervisor:which_children(SupPid)
    ),
    {_Id, TargetPid, _Type, _Mods} = Child,
    true = is_pid(TargetPid),
    {ok, Tree} = ides:ancestors(TargetPid),
    Output = lists:flatten(ides:format(TargetPid, Tree)),
    [Check(Output) || Check <- Checks].

assert_target_line_contains(Substring, Output) ->
    [TL | _] = [
        L
     || L <- string:split(Output, "\n", all),
        string:prefix(L, "  * ") =/= nomatch
    ],
    ?assert(string:find(TL, Substring) =/= nomatch).

assert_line_count(Expected, Output) ->
    Lines = string:split(string:trim(Output, trailing), "\n", all),
    ?assertEqual(Expected, length(Lines)).

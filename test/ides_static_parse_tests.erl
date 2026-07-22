-module(ides_static_parse_tests).

-include_lib("eunit/include/eunit.hrl").

compile_test_beam(ModuleName, SourceBody) ->
    SrcFile = filename:join(["test", "support", atom_to_list(ModuleName) ++ ".erl"]),
    ok = file:write_file(SrcFile, SourceBody),
    {ok, _Mod, Beam} = compile:file(SrcFile, [debug_info, binary, report, {outdir, "test/support"}]),
    BeamFile = filename:rootname(SrcFile) ++ ".beam",
    ok = file:write_file(BeamFile, Beam),
    {ok, #{ModuleName := Info}} = ides_static_beam:load_beams([BeamFile]),
    Info.

parse_one_for_one_sup_flags_test() ->
    Info = compile_test_beam(test_parse_1,
        "-module(test_parse_1).\n"
        "-behaviour(supervisor).\n"
        "-export([start_link/0, init/1]).\n"
        "start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n"
        "init([]) ->\n"
        "    SupFlags = #{strategy => one_for_one, intensity => 3, period => 10},\n"
        "    {ok, {SupFlags, []}}.\n"
    ),
    {ok, SupFlags, []} = ides_static_parse:parse_init(Info),
    ?assertEqual(one_for_one, maps:get(strategy, SupFlags)),
    ?assertEqual(3, maps:get(intensity, SupFlags)),
    ?assertEqual(10, maps:get(period, SupFlags)).

parse_simple_one_for_one_test() ->
    Info = compile_test_beam(test_parse_s1o1,
        "-module(test_parse_s1o1).\n"
        "-behaviour(supervisor).\n"
        "-export([start_link/0, init/1]).\n"
        "start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n"
        "init([]) ->\n"
        "    SupFlags = #{strategy => simple_one_for_one, intensity => 5, period => 60},\n"
        "    {ok, {SupFlags, []}}.\n"
    ),
    {ok, SupFlags, []} = ides_static_parse:parse_init(Info),
    ?assertEqual(simple_one_for_one, maps:get(strategy, SupFlags)),
    ?assertEqual(5, maps:get(intensity, SupFlags)),
    ?assertEqual(60, maps:get(period, SupFlags)).

parse_child_specs_test() ->
    Info = compile_test_beam(test_parse_kids,
        "-module(test_parse_kids).\n"
        "-behaviour(supervisor).\n"
        "-export([start_link/0, init/1]).\n"
        "start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n"
        "init([]) ->\n"
        "    SupFlags = #{strategy => one_for_one, intensity => 1, period => 5},\n"
        "    Children = [\n"
        "        #{id => w1, start => {static_worker, start_link, []}, restart => permanent, type => worker, modules => [static_worker]},\n"
        "        #{id => w2, start => {static_worker, start_link, []}, restart => transient, type => worker, modules => [static_worker]}\n"
        "    ],\n"
        "    {ok, {SupFlags, Children}}.\n"
    ),
    {ok, _SupFlags, Children} = ides_static_parse:parse_init(Info),
    ?assertEqual(2, length(Children)),
    [Child1, Child2] = Children,
    ?assertEqual(w1, maps:get(id, Child1)),
    ?assertEqual({static_worker, start_link, []}, maps:get(start, Child1)),
    ?assertEqual(permanent, maps:get(restart, Child1)),
    ?assertEqual(worker, maps:get(type, Child1)),
    ?assertEqual(w2, maps:get(id, Child2)),
    ?assertEqual(transient, maps:get(restart, Child2)).

parse_supervisor_child_type_test() ->
    Info = compile_test_beam(test_parse_sup_child,
        "-module(test_parse_sup_child).\n"
        "-behaviour(supervisor).\n"
        "-export([start_link/0, init/1]).\n"
        "start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n"
        "init([]) ->\n"
        "    SupFlags = #{strategy => one_for_one, intensity => 1, period => 5},\n"
        "    Children = [\n"
        "        #{id => sub_sup, start => {test_parse_1, start_link, []}, restart => permanent, type => supervisor, modules => [test_parse_1]}\n"
        "    ],\n"
        "    {ok, {SupFlags, Children}}.\n"
    ),
    {ok, _SupFlags, Children} = ides_static_parse:parse_init(Info),
    [Child] = Children,
    ?assertEqual(supervisor, maps:get(type, Child)).

parse_no_abstract_code_test() ->
    Info = #{module => test_no_abstr, attributes => [{behaviour, [supervisor]}], exports => [{init, 1}]},
    ?assertMatch({error, no_abstract_code}, ides_static_parse:parse_init(Info)).

parse_not_a_supervisor_test() ->
    Info = compile_test_beam(test_not_sup_parse,
        "-module(test_not_sup_parse).\n"
        "-export([init/1]).\n"
        "init([]) -> {ok, #{}}.\n"
    ),
    ?assertMatch({error, _}, ides_static_parse:parse_init(Info)).

-module(ides_cli_tests).

-include_lib("eunit/include/eunit.hrl").

fixture_project() ->
    Base = "/tmp/ides_cli_fixture_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = file:make_dir(Base),
    ok = file:make_dir(filename:join(Base, "src")),
    Ebin = filename:join([Base, "_build", "default", "lib", "fixture", "ebin"]),
    ok = filelib:ensure_dir(filename:join(Ebin, "placeholder")),
    ok = file:write_file(
        filename:join([Base, "src", "fixture.app.src"]),
        "{application, fixture, [{vsn, \"0.1.0\"}, {applications, "
        "[kernel, stdlib]}, {modules, []}]}."
    ),
    Sources = [
        {"static_worker.erl",
            "-module(static_worker).\n"
            "-behaviour(gen_server).\n"
            "-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2]).\n"
            "start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n"
            "init([]) -> {ok, #{}}.\n"
            "handle_call(_Req, _From, State) -> {reply, ok, State}.\n"
            "handle_cast(_Msg, State) -> {noreply, State}.\n"
            "handle_info(_Msg, State) -> {noreply, State}.\n"},
        {"static_one_for_one_sup.erl",
            "-module(static_one_for_one_sup).\n"
            "-behaviour(supervisor).\n"
            "-export([start_link/0, init/1]).\n"
            "start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n"
            "init([]) ->\n"
            "    SupFlags = #{strategy => one_for_one, intensity => 3, period => 10},\n"
            "    Children = [\n"
            "        #{id => worker_a, start => {static_worker, start_link, []}, "
            "restart => permanent, type => worker, modules => [static_worker]},\n"
            "        #{id => worker_b, start => {static_worker, start_link, []}, "
            "restart => transient, type => worker, modules => [static_worker]},\n"
            "        #{id => static_simple_one_for_one_sup, start => "
            "{static_simple_one_for_one_sup, start_link, []}, restart => permanent, "
            "type => supervisor, modules => [static_simple_one_for_one_sup]}\n"
            "    ],\n"
            "    {ok, {SupFlags, Children}}.\n"},
        {"static_simple_one_for_one_sup.erl",
            "-module(static_simple_one_for_one_sup).\n"
            "-behaviour(supervisor).\n"
            "-export([start_link/0, init/1]).\n"
            "start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n"
            "init([]) ->\n"
            "    SupFlags = #{strategy => simple_one_for_one, intensity => 5, period => 5},\n"
            "    ChildSpec = #{id => static_worker, start => {static_worker, start_link, []}, "
            "restart => temporary, type => worker, modules => [static_worker]},\n"
            "    {ok, {SupFlags, [ChildSpec]}}.\n"}
    ],
    lists:foreach(
        fun({Name, Source}) ->
            SrcPath = filename:join([Base, "src", Name]),
            ok = file:write_file(SrcPath, Source),
            {ok, Mod, Beam} = compile:file(SrcPath, [debug_info, binary, report, return_errors]),
            ok = file:write_file(filename:join(Ebin, atom_to_list(Mod) ++ ".beam"), Beam)
        end,
        Sources
    ),
    Base.

cleanup(Base) ->
    file:del_dir_r(Base).

full_tree_test() ->
    Base = fixture_project(),
    try
        {ok, Out} = ides_cli:run([Base]),
        Flat = lists:flatten(Out),
        ?assert(string:str(Flat, "static_one_for_one_sup") > 0),
        ?assert(string:str(Flat, "worker_a") > 0),
        ?assertEqual(0, string:str(Flat, "* "))
    after
        cleanup(Base)
    end.

target_by_module_test() ->
    Base = fixture_project(),
    try
        {ok, Out} = ides_cli:run([Base, "--target", "static_worker"]),
        Flat = lists:flatten(Out),
        ?assert(string:str(Flat, "* worker_a") > 0),
        ?assert(string:str(Flat, "* worker_b") > 0)
    after
        cleanup(Base)
    end.

target_by_id_test() ->
    Base = fixture_project(),
    try
        {ok, Out} = ides_cli:run([Base, "--target", "worker_a"]),
        Flat = lists:flatten(Out),
        ?assert(string:str(Flat, "* worker_a") > 0)
    after
        cleanup(Base)
    end.

target_not_found_test() ->
    Base = fixture_project(),
    try
        ?assertMatch({error, _, 1}, ides_cli:run([Base, "--target", "nope"]))
    after
        cleanup(Base)
    end.

warnings_flag_test() ->
    Base = fixture_project(),
    try
        {ok, Out} = ides_cli:run([Base, "--warnings"]),
        Flat = lists:flatten(Out),
        ?assert(
            string:str(
                Flat,
                "ides: warning: dynamic child spec: "
                "static_simple_one_for_one_sup"
            ) > 0
        )
    after
        cleanup(Base)
    end.

no_warnings_by_default_test() ->
    Base = fixture_project(),
    try
        {ok, Out} = ides_cli:run([Base]),
        Flat = lists:flatten(Out),
        ?assertEqual(0, string:str(Flat, "warning:"))
    after
        cleanup(Base)
    end.

help_test() ->
    ?assertMatch({ok, _}, ides_cli:run(["--help"])),
    ?assertMatch({ok, _}, ides_cli:run(["-h"])).

missing_path_usage_error_test() ->
    ?assertMatch({error, _, 2}, ides_cli:run([])).

unknown_flag_usage_error_test() ->
    ?assertMatch({error, _, 2}, ides_cli:run(["--bogus", "x"])).

missing_build_test() ->
    Base = fixture_project(),
    try
        ok = file:del_dir_r(filename:join(Base, "_build")),
        ?assertMatch({error, _, 1}, ides_cli:run([Base]))
    after
        cleanup(Base)
    end.

missing_project_test() ->
    ?assertMatch({error, _, 1}, ides_cli:run(["/nonexistent/project/path"])).

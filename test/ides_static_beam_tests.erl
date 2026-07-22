-module(ides_static_beam_tests).

-include_lib("eunit/include/eunit.hrl").

compile_test_beam(ModuleName, SourceBody) ->
    SrcFile = filename:join(["priv", "support", atom_to_list(ModuleName) ++ ".erl"]),
    ok = file:write_file(SrcFile, SourceBody),
    {ok, _Mod, Beam} = compile:file(SrcFile, [debug_info, binary, report, return_errors]),
    file:delete(SrcFile),
    Beam.

load_supervisor_beam_test() ->
    BeamFile = compile_test_beam(test_beam_sup,
        "-module(test_beam_sup).\n"
        "-behaviour(supervisor).\n"
        "-export([start_link/0, init/1]).\n"
        "start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n"
        "init([]) -> {ok, {#{strategy => one_for_one, intensity => 1, period => 5}, []}}.\n"
    ),
    {ok, BeamMap} = ides_static_beam:load_beams([BeamFile]),
    ?assert(maps:is_key(test_beam_sup, BeamMap)),
    #{test_beam_sup := Info} = BeamMap,
    ?assertEqual(test_beam_sup, maps:get(module, Info)),
    ?assert(is_list(maps:get(attributes, Info))),
    ?assert(is_list(maps:get(exports, Info))),
    ?assert(is_list(maps:get(abstract_code, Info))).

load_non_supervisor_beam_test() ->
    BeamFile = compile_test_beam(test_beam_gen,
        "-module(test_beam_gen).\n"
        "-behaviour(gen_server).\n"
        "-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2]).\n"
        "start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n"
        "init([]) -> {ok, #{}}.\n"
        "handle_call(_R, _F, S) -> {reply, ok, S}.\n"
        "handle_cast(_M, S) -> {noreply, S}.\n"
        "handle_info(_M, S) -> {noreply, S}.\n"
    ),
    {ok, BeamMap} = ides_static_beam:load_beams([BeamFile]),
    ?assert(maps:is_key(test_beam_gen, BeamMap)).

is_supervisor_test() ->
    SupCode = compile_test_beam(test_sup_check,
        "-module(test_sup_check).\n"
        "-behaviour(supervisor).\n"
        "-export([start_link/0, init/1]).\n"
        "start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).\n"
        "init([]) -> {ok, {#{strategy => one_for_one, intensity => 1, period => 5}, []}}.\n"
    ),
    {ok, BeamMap} = ides_static_beam:load_beams([SupCode]),
    #{test_sup_check := Info} = BeamMap,
    ?assert(ides_static_beam:is_supervisor(Info)).

is_not_supervisor_test() ->
    GenCode = compile_test_beam(test_not_sup,
        "-module(test_not_sup).\n"
        "-behaviour(gen_server).\n"
        "-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2]).\n"
        "start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n"
        "init([]) -> {ok, #{}}.\n"
        "handle_call(_R, _F, S) -> {reply, ok, S}.\n"
        "handle_cast(_M, S) -> {noreply, S}.\n"
        "handle_info(_M, S) -> {noreply, S}.\n"
    ),
    {ok, BeamMap} = ides_static_beam:load_beams([GenCode]),
    #{test_not_sup := Info} = BeamMap,
    ?assertNot(ides_static_beam:is_supervisor(Info)).

missing_file_test() ->
    {ok, BeamMap} = ides_static_beam:load_beams(["nonexistent.beam"]),
    ?assertEqual(#{}, BeamMap).

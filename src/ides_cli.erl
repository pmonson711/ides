-module(ides_cli).

-moduledoc "Command-line escript for printing static ides supervision trees "
"from rebar3 project BEAM files.".

-export([main/1, run/1]).

-doc "Escript entry point.".
-spec main([string()]) -> no_return().

main(Args) ->
    case run(Args) of
        {ok, Out} ->
            io:put_chars(Out),
            halt(0);
        {error, Out, Code} ->
            io:put_chars(standard_error, Out),
            halt(Code)
    end.

-doc """
Run the CLI, returning the output and an implied exit code so the logic is testable.

Returns `{ok, iolist()}` for exit 0, or `{error, iolist(), Code}` where the iolist
goes to stderr and Code is `1` (runtime) or `2` (usage).
""".
-spec run([string()]) -> {ok, iolist()} | {error, iolist(), 1 | 2}.

run(Args) ->
    case parse_args(Args) of
        help ->
            {ok, usage_text()};
        {error, Msg} ->
            {error, ["ides: ", Msg, "\n", usage_text()], 2};
        {ok, Opts} ->
            case execute(Opts) of
                {ok, Out} -> {ok, Out};
                {error, Msg} -> {error, ["ides: ", Msg, "\n"], 1}
            end
    end.

execute(#{project := Project} = Opts) ->
    Deps = maps:get(deps, Opts, false),
    case discover_ebins(Project, Deps) of
        {ok, Beams} ->
            case ides_static:supervisor_tree(Beams) of
                {ok, #{tree := Tree, warnings := Warnings}} ->
                    case render_tree(Opts, #{tree => Tree, warnings => Warnings}) of
                        {ok, TreeOut} ->
                            WarnOut = maybe_warnings(Opts, Warnings),
                            {ok, [TreeOut, WarnOut]};
                        {error, Msg} ->
                            {error, Msg}
                    end;
                {error, Reason} ->
                    {error, "static analysis failed: " ++ format_reason(Reason)}
            end;
        {error, Msg} ->
            {error, Msg}
    end.

render_tree(#{target := Target}, T) when Target =/= undefined ->
    case ides_static:find_by_target(Target, T) of
        {ok, Mod} -> {ok, ides_static:format(Mod, T)};
        {error, not_found} -> {error, "target '" ++ Target ++ "' not found"}
    end;
render_tree(_Opts, T) ->
    {ok, ides_static:format_tree(T)}.

maybe_warnings(#{warnings := true}, Warnings) ->
    format_warnings(Warnings);
maybe_warnings(_Opts, _Warnings) ->
    "".

format_warnings(Warnings) ->
    [format_warning(W) || W <- Warnings].

format_warning({dynamic_child_spec, M}) ->
    io_lib:format("ides: warning: dynamic child spec: ~p~n", [M]);
format_warning({unresolvable_module, M}) ->
    io_lib:format("ides: warning: unresolvable module: ~p~n", [M]);
format_warning({missing_behaviour, M}) ->
    io_lib:format("ides: warning: missing behaviour: ~p~n", [M]).

discover_ebins(Project, Deps) ->
    AppSrcFiles = filelib:wildcard(filename:join([Project, "src", "*.app.src"])),
    case AppSrcFiles of
        [] ->
            {error, "no src/*.app.src found (not a rebar3 app?)"};
        [AppSrc] ->
            App = filename:basename(AppSrc, ".app.src"),
            BuildLib = filename:join([Project, "_build", "default", "lib"]),
            case filelib:is_dir(BuildLib) of
                false ->
                    {error, "no _build directory; run `rebar3 compile` first"};
                true ->
                    EbinDirs =
                        case Deps of
                            true ->
                                filelib:wildcard(
                                    filename:join(filename:join(BuildLib, "*"), "ebin")
                                );
                            false ->
                                [filename:join(filename:join(BuildLib, App), "ebin")]
                        end,
                    Beams = lists:append(
                        [filelib:wildcard(filename:join(E, "*.beam")) || E <- EbinDirs]
                    ),
                    case Beams of
                        [] -> {error, "no .beam files found; run `rebar3 compile` first"};
                        _ -> {ok, lists:sort(Beams)}
                    end
            end;
        _Multiple ->
            {error, "multiple src/*.app.src files found; only single-app projects are supported"}
    end.

parse_args(Args) ->
    parse_args(Args, #{deps => false, warnings => false, target => undefined}, undefined).

parse_args([], Opts, Project) ->
    case Project of
        undefined -> {error, "missing <project-path>"};
        _ -> {ok, Opts#{project => Project}}
    end;
parse_args(["--help" | _], _Opts, _Project) ->
    help;
parse_args(["-h" | _], _Opts, _Project) ->
    help;
parse_args(["--deps" | Rest], Opts, Project) ->
    parse_args(Rest, Opts#{deps => true}, Project);
parse_args(["--warnings" | Rest], Opts, Project) ->
    parse_args(Rest, Opts#{warnings => true}, Project);
parse_args(["--target", Target | Rest], Opts, Project) ->
    parse_args(Rest, Opts#{target => Target}, Project);
parse_args(["--target"], _Opts, _Project) ->
    {error, "missing value for --target"};
parse_args([["--" | _] = Flag | _], _Opts, _Project) ->
    {error, "unknown option: " ++ Flag};
parse_args([["-" | _] = Flag | _], _Opts, _Project) ->
    {error, "unknown option: " ++ Flag};
parse_args([Arg | Rest], Opts, undefined) ->
    parse_args(Rest, Opts, Arg);
parse_args([_ | _], _Opts, _Project) ->
    {error, "too many arguments"}.

usage_text() ->
    "usage: ides <project-path> [--deps] [--warnings] [--target T] [--help|-h]\n".

format_reason(Reason) ->
    lists:flatten(io_lib:format("~p", [Reason])).

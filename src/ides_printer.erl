-module(ides_printer).

-moduledoc "Formatting and rendering for ides supervision trees.".

-export([
    format/2,
    print/2,
    format_detail/3,
    print_detail/3,
    format_init_analysis/1,
    print_init_analysis/1
]).

-doc """
Render the supervision tree as indented ASCII text.
The target process is marked with `*`. Indentation is 4 spaces
per level.

Rendering rules:
- Root supervisor: `name (strategy)`
- Supervisor child: `name (strategy, restart_type)`
- Worker child: `name (restart_type)`
- Target process: prefixed with `* `
""".
-spec format(TargetPid :: pid(), Tree :: ides_family:process()) -> iolist().
format(TargetPid, Tree) ->
    format_node(TargetPid, Tree, 0).

-spec format_node(TargetPid :: pid(), Node :: ides_family:process(), Depth :: non_neg_integer()) ->
    iolist().
format_node(
    TargetPid,
    #{
        name := Name,
        pid := Pid,
        type := supervisor,
        strategy := Strategy,
        restart_type := RestartType,
        children := Children
    },
    Depth
) ->
    Prefix = prefix(TargetPid, Pid, Depth),
    Anno = [supervisor_anno(Strategy, RestartType, Pid)],
    [
        Prefix,
        Name,
        Anno,
        "\n"
        | [format_node(TargetPid, Child, Depth + 1) || Child <- Children]
    ];
format_node(
    TargetPid,
    #{
        name := Name,
        pid := Pid,
        type := supervisor,
        strategy := Strategy,
        children := Children
    },
    Depth
) ->
    Prefix = prefix(TargetPid, Pid, Depth),
    Anno = [supervisor_anno(Strategy, Pid)],
    [
        Prefix,
        Name,
        Anno,
        "\n"
        | [format_node(TargetPid, Child, Depth + 1) || Child <- Children]
    ];
format_node(
    TargetPid,
    #{
        name := Name,
        pid := Pid,
        type := worker,
        restart_type := RestartType
    },
    Depth
) ->
    Prefix = prefix(TargetPid, Pid, Depth),
    Anno = [" (", atom_to_list(RestartType), ")"],
    [Prefix, Name, Anno, "\n"].

-spec prefix(TargetPid :: pid(), Pid :: pid(), Depth :: non_neg_integer()) -> [string()].
prefix(_TargetPid, _Pid, 0) ->
    [""];
prefix(TargetPid, Pid, Depth) ->
    Indent = spaces(Depth * 4 - 2),
    [Indent, marker(TargetPid, Pid)].

-spec spaces(non_neg_integer()) -> string().
spaces(0) -> "";
spaces(N) -> [$\s | spaces(N - 1)].

-spec marker(TargetPid :: pid(), Pid :: pid()) -> string().
marker(TargetPid, TargetPid) -> "* ";
marker(_TargetPid, _Pid) -> "  ".

-spec supervisor_anno(Strategy :: atom(), RestartType :: atom(), Pid :: pid()) -> iolist().
supervisor_anno(Strategy, RestartType, Pid) ->
    [[" (", atom_to_list(Strategy), ", ", atom_to_list(RestartType), intensity_suffix(Pid), ")"]].

-spec supervisor_anno(Strategy :: atom(), Pid :: pid()) -> iolist().
supervisor_anno(Strategy, Pid) ->
    [[" (", atom_to_list(Strategy), intensity_suffix(Pid), ")"]].

-spec intensity_suffix(Pid :: pid()) -> iolist().
intensity_suffix(Pid) ->
    case ides_march:intensity_info(Pid) of
        {ok, #{max_restarts := MaxR, max_period := MaxT, current_count := Count}} ->
            io_lib:format(", ~p/~p in ~ps", [Count, MaxR, MaxT]);
        {ok, #{max_restarts := MaxR, max_period := MaxT}} ->
            io_lib:format(", max ~p/~ps", [MaxR, MaxT]);
        _ ->
            []
    end.

-doc """
Like `format/2` but writes the rendered tree to stdout.
""".
-spec print(TargetPid :: pid(), Tree :: ides_family:process()) -> ok.
print(TargetPid, Tree) ->
    io:put_chars(format(TargetPid, Tree)).

-doc """
Like `format/2` but also includes a section showing link
and monitor relationships below the tree.

`KillSources` is the result of `ides_march:kill_graph_detail/1`.
""".
-spec format_detail(
    TargetPid :: pid(), Tree :: ides_family:process(), KillSources :: [ides_family:kill_source()]
) -> iolist().
format_detail(TargetPid, Tree, KillSources) ->
    TreePart = format(TargetPid, Tree),
    KillPart = format_kill_sources(KillSources),
    [TreePart, "\nKill Graph:\n", KillPart].

-spec print_detail(
    TargetPid :: pid(), Tree :: ides_family:process(), KillSources :: [ides_family:kill_source()]
) -> ok.
print_detail(TargetPid, Tree, KillSources) ->
    io:put_chars(format_detail(TargetPid, Tree, KillSources)).

-doc """
Render the init analysis result as a human-readable summary.
""".
-spec format_init_analysis(Result :: ides_family:init_analysis_result()) -> iolist().
format_init_analysis(#{
    supervisor := SupPid,
    sup_strategy := Strategy,
    sup_intensity := Intensity,
    target_pid := TargetPid,
    total_children := Total,
    children := Children,
    worst_case_restarts := WorstCase,
    remaining_budget := Budget
}) ->
    SupLine = format_sup_header(SupPid, Strategy, Intensity),
    ChildrenLines = [format_child_info(C, TargetPid) || C <- Children],
    Footer = format_budget_footer(Budget, WorstCase),
    [
        SupLine,
        io_lib:format("Total children: ~p~n", [Total]),
        io_lib:format("Worst-case restart count: ~p~n", [WorstCase]),
        io_lib:format("~nChildren:~n", []),
        lists:join("\n", ChildrenLines),
        "\n",
        Footer
    ].

-doc """
Like `format_init_analysis/1` but writes to stdout.
""".
-spec print_init_analysis(Result :: ides_family:init_analysis_result()) -> ok.
print_init_analysis(Result) ->
    io:put_chars(format_init_analysis(Result)).

%% --- Internal helpers for init_analysis formatting ---

-spec format_sup_header(
    SupPid :: pid(), Strategy :: atom(), Intensity :: ides_family:intensity_info()
) ->
    iolist().
format_sup_header(SupPid, Strategy, Intensity) ->
    SupName = pid_to_list(SupPid),
    case Intensity of
        #{max_restarts := MaxR, max_period := MaxT, current_count := Count} ->
            Remaining = max(0, MaxR - Count),
            io_lib:format(
                "Supervisor: ~s (~s, max ~p/~ps, ~p restarts remaining)~n",
                [SupName, atom_to_list(Strategy), MaxR, MaxT, Remaining]
            );
        #{max_restarts := MaxR, max_period := MaxT} ->
            io_lib:format(
                "Supervisor: ~s (~s, max ~p/~ps)~n",
                [SupName, atom_to_list(Strategy), MaxR, MaxT]
            )
    end.

-spec format_child_info(Info :: ides_family:child_init_info(), TargetPid :: pid()) -> iolist().
format_child_info(
    #{
        id := Id,
        pid := Pid,
        restart_type := RestartType,
        shutdown := Shutdown,
        counts_against_intensity := Counts
    },
    TargetPid
) ->
    Marker =
        case Pid of
            TargetPid -> "* ";
            _ -> "  "
        end,
    IdStr = io_lib:format("~p", [Id]),
    ShutdownStr =
        case Shutdown of
            infinity -> "infinity";
            Ms when is_integer(Ms) -> io_lib:format("~p", [Ms])
        end,
    Anno =
        case {Counts, RestartType} of
            {false, _} ->
                io_lib:format("(~s, shutdown=~s)    never restarted", [
                    atom_to_list(RestartType), ShutdownStr
                ]);
            _ ->
                io_lib:format("(~s, shutdown=~s)", [atom_to_list(RestartType), ShutdownStr])
        end,
    ["    ", Marker, IdStr, "  ", Anno].

-spec format_budget_footer(Budget :: integer(), WorstCase :: non_neg_integer()) -> iolist().
format_budget_footer(Budget, WorstCase) when Budget < 0 ->
    io_lib:format(
        "Remaining budget: exceeded by ~p. Worst case: ~p.~n",
        [abs(Budget), WorstCase]
    );
format_budget_footer(Budget, WorstCase) when Budget < WorstCase ->
    io_lib:format(
        "Remaining budget: ~p. Worst case: ~p. WARNING: worst-case restarts (~p) exceeds remaining budget (~p).~n",
        [Budget, WorstCase, WorstCase, Budget]
    );
format_budget_footer(Budget, WorstCase) ->
    io_lib:format(
        "Remaining budget: ~p. Worst case: ~p.~n",
        [Budget, WorstCase]
    ).

%% --- Internal ---

-spec format_kill_sources(Sources :: [ides_family:kill_source()]) -> iolist().
format_kill_sources([]) ->
    ["  (none)\n"];
format_kill_sources(Sources) ->
    Ancestors = [P || {ancestor, P} <- Sources],
    Siblings = [P || {sibling, P} <- Sources],
    Links = [P || {link, P} <- Sources],
    Monitors = [P || {monitor, P} <- Sources],
    [
        format_kill_group("  ancestors", Ancestors),
        format_kill_group("  siblings ", Siblings),
        format_kill_group("  links    ", Links),
        format_kill_group("  monitors ", Monitors)
    ].

-spec format_kill_group(Label :: string(), Pids :: [pid()]) -> iolist().
format_kill_group(_Label, []) ->
    [];
format_kill_group(Label, Pids) ->
    PidStrs = [io_lib:format("~p", [P]) || P <- lists:sort(Pids)],
    [Label, ": ", string:join(PidStrs, ", "), "\n"].

-module(ides_printer).

-moduledoc "Formatting and rendering for ides supervision trees.".

-export([format/2, print/2, format_detail/3, print_detail/3]).

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
    Anno = [" (", atom_to_list(Strategy), ", ", atom_to_list(RestartType), ")"],
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
    Anno = [" (", atom_to_list(Strategy), ")"],
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

-doc """
Like `format/2` but writes the rendered tree to stdout.
""".
-spec print(TargetPid :: pid(), Tree :: ides_family:process()) -> ok.
print(TargetPid, Tree) ->
    io:put_chars(format(TargetPid, Tree)).

-doc #{
    f => format_detail,
    a => 3,
    d =>
        "Like `format/2` but also includes a section showing link\\n"
        "and monitor relationships below the tree.\\n"
        "\\n"
        "`KillSources` is the result of `ides_march:kill_graph_detail/1`."
}.
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

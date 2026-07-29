-module(ides_prettypr).

-moduledoc "Prettypr-based formatting for ides supervision trees.".

-export([format/2, print/2]).

-doc """
Render the supervision tree as indented ASCII text using prettypr.
The target process is marked with `*`. Indentation is 4 spaces
per level.

Output is byte-identical to ides_printer:format/2.
""".
-spec format(TargetPid :: pid(), Tree :: ides_family:process()) -> iolist().
format(TargetPid, Tree) ->
    Doc = format_node(TargetPid, Tree, 0),
    [prettypr:format(Doc), "\n"].

-doc """
Like `format/2` but writes the rendered tree to stdout.
""".
-spec print(TargetPid :: pid(), Tree :: ides_family:process()) -> ok.
print(TargetPid, Tree) ->
    io:put_chars(format(TargetPid, Tree)).

%% --- Internal ---

-spec format_node(TargetPid :: pid(), Node :: ides_family:process(), Depth :: non_neg_integer()) ->
    prettypr:document().
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
    Line = format_supervisor_line(TargetPid, Pid, Name, Depth, Strategy, RestartType),
    format_children(TargetPid, Line, Children, Depth);
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
    Line = format_supervisor_line(TargetPid, Pid, Name, Depth, Strategy),
    format_children(TargetPid, Line, Children, Depth);
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
    Prefix = line_prefix(TargetPid, Pid, Depth),
    Anno = [" (", atom_to_list(RestartType), ")"],
    prettypr:text(binary_to_list(iolist_to_binary([Prefix, Name, Anno]))).

-spec format_supervisor_line(
    TargetPid :: pid(),
    Pid :: pid(),
    Name :: string(),
    Depth :: non_neg_integer(),
    Strategy :: atom(),
    RestartType :: atom()
) -> prettypr:document().
format_supervisor_line(TargetPid, Pid, Name, Depth, Strategy, RestartType) ->
    Prefix = line_prefix(TargetPid, Pid, Depth),
    Anno = [
        " (", atom_to_list(Strategy), ", ", atom_to_list(RestartType), intensity_suffix(Pid), ")"
    ],
    prettypr:text(binary_to_list(iolist_to_binary([Prefix, Name, Anno]))).

-spec format_supervisor_line(
    TargetPid :: pid(),
    Pid :: pid(),
    Name :: string(),
    Depth :: non_neg_integer(),
    Strategy :: atom()
) -> prettypr:document().
format_supervisor_line(TargetPid, Pid, Name, Depth, Strategy) ->
    Prefix = line_prefix(TargetPid, Pid, Depth),
    Anno = [" (", atom_to_list(Strategy), intensity_suffix(Pid), ")"],
    prettypr:text(binary_to_list(iolist_to_binary([Prefix, Name, Anno]))).

-spec format_children(
    TargetPid :: pid(),
    Line :: prettypr:document(),
    Children :: [ides_family:process()],
    Depth :: non_neg_integer()
) -> prettypr:document().
format_children(_TargetPid, Line, [], _Depth) ->
    Line;
format_children(TargetPid, Line, [Child | Rest], Depth) ->
    ChildDoc = format_node(TargetPid, Child, Depth + 1),
    format_children(TargetPid, prettypr:above(Line, ChildDoc), Rest, Depth).

-spec line_prefix(TargetPid :: pid(), Pid :: pid(), Depth :: non_neg_integer()) -> string().
line_prefix(_TargetPid, _Pid, 0) ->
    "";
line_prefix(TargetPid, Pid, Depth) ->
    Indent = spaces(Depth * 4 - 2),
    Marker = marker(TargetPid, Pid),
    Indent ++ Marker.

-spec spaces(non_neg_integer()) -> string().
spaces(0) -> "";
spaces(N) -> [$\s | spaces(N - 1)].

-spec marker(TargetPid :: pid(), Pid :: pid()) -> string().
marker(TargetPid, TargetPid) -> "* ";
marker(_TargetPid, _Pid) -> "  ".

-spec intensity_suffix(Pid :: pid()) -> iolist().
intensity_suffix(Pid) ->
    case ides_march:intensity_info(Pid) of
        {ok, #{max_restarts := MaxR, max_period := MaxT, current_count := Count}} ->
            io_lib:format(", ~p/~p in ~ps", [Count, MaxR, MaxT]);
        {ok, #{max_restarts := MaxR, max_period := MaxT}} ->
            io_lib:format(", max ~p/~ps", [MaxR, MaxT])
    end.

-module(ides_printer).

-doc "Formatting and rendering for ides supervision trees.".

-export([format/2, print/2]).

-doc #{
    f => format,
    a => 2,
    d =>
        "Render the supervision tree as indented ASCII text.\n"
        "The target process is marked with `*`. Indentation is 4 spaces\n"
        "per level.\n"
        "\n"
        "Rendering rules:\n"
        "- Root supervisor: `name (strategy)`\n"
        "- Supervisor child: `name (strategy, restart_type)`\n"
        "- Worker child: `name (restart_type)`\n"
        "- Target process: prefixed with `* `"
}.
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

-doc #{
    f => print,
    a => 2,
    d => "Like `format/2` but writes the rendered tree to stdout."
}.
-spec print(TargetPid :: pid(), Tree :: ides_family:process()) -> ok.
print(TargetPid, Tree) ->
    io:put_chars(format(TargetPid, Tree)).

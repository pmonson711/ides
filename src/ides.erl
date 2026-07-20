-module(ides).

-export([ancestors/1, format/2, print/2]).

-type supervisor_strategy() :: one_for_one
                             | one_for_all
                             | rest_for_one
                             | simple_one_for_one.

-type child_restart_type() :: permanent
                             | transient
                             | temporary.

-type child_process() :: #{
    name         := string(),
    pid          := pid(),
    type         := worker,
    restart_type := child_restart_type()
}.

-type supervisor_process() :: #{
    name         := string(),
    pid          := pid(),
    type         := supervisor,
    strategy     := supervisor_strategy(),
    restart_type => child_restart_type(),
    children     := [process()]
}.

-type process() :: supervisor_process() | child_process().

-export_type([process/0, supervisor_process/0, child_process/0,
              supervisor_strategy/0, child_restart_type/0]).

-spec ancestors(TargetPid :: pid()) -> {ok, process()} | {error, term()}.
ancestors(_TargetPid) ->
    {error, not_implemented}.

-spec format(TargetPid :: pid(), Tree :: process()) -> iolist().
format(TargetPid, Tree) ->
    format_node(TargetPid, Tree, 0).

-spec format_node(TargetPid :: pid(), Node :: process(), Depth :: non_neg_integer()) -> iolist().
format_node(TargetPid, #{name := Name, pid := Pid, type := supervisor,
                          strategy := Strategy, restart_type := RestartType,
                          children := Children}, Depth) ->
    Prefix = prefix(TargetPid, Pid, Depth),
    Anno = [" (", atom_to_list(Strategy), ", ", atom_to_list(RestartType), ")"],
    [Prefix, Name, Anno, "\n" |
     [format_node(TargetPid, Child, Depth + 1) || Child <- Children]];
format_node(TargetPid, #{name := Name, pid := Pid, type := supervisor,
                          strategy := Strategy, children := Children}, Depth) ->
    Prefix = prefix(TargetPid, Pid, Depth),
    Anno = [" (", atom_to_list(Strategy), ")"],
    [Prefix, Name, Anno, "\n" |
     [format_node(TargetPid, Child, Depth + 1) || Child <- Children]];
format_node(TargetPid, #{name := Name, pid := Pid, type := worker,
                          restart_type := RestartType}, Depth) ->
    Prefix = prefix(TargetPid, Pid, Depth),
    Anno = [" (", atom_to_list(RestartType), ")"],
    [Prefix, Name, Anno, "\n"].

-spec prefix(TargetPid :: pid(), Pid :: pid(), Depth :: non_neg_integer()) -> iolist().
prefix(_TargetPid, _Pid, 0) -> "";
prefix(TargetPid, Pid, Depth) ->
    Indent = lists:duplicate(Depth * 4 - 2, $\s),
    [Indent, marker(TargetPid, Pid)].

-spec marker(TargetPid :: pid(), Pid :: pid()) -> string().
marker(TargetPid, TargetPid) -> "* ";
marker(_TargetPid, _Pid)      -> "  ".

-spec print(TargetPid :: pid(), Tree :: process()) -> ok.
print(TargetPid, Tree) ->
    io:put_chars(format(TargetPid, Tree)).

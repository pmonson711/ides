-module(ides_march).

-doc "Kill graph analysis and restart logic for ides.".

-export([kill_graph/1, should_restart/2, affected_siblings/1]).

-type exit_reason() :: normal | abnormal.
-export_type([exit_reason/0]).

-doc #{
    f => kill_graph,
    a => 1,
    d =>
        "Return all PIDs that could cause `TargetPid` to be killed.\n"
        "\n"
        "This is the set of ancestors unioned with siblings that trigger\n"
        "cascade restarts under the parent supervisor's strategy:\n"
        "- `one_for_one` / `simple_one_for_one`: only ancestors (no\n"
        "  sibling killers)\n"
        "- `one_for_all`: all siblings are killers\n"
        "- `rest_for_one`: siblings at positions before the target are\n"
        "  killers"
}.
-spec kill_graph(TargetPid :: pid()) -> {ok, [pid()]} | {error, term()}.
kill_graph(TargetPid) ->
    case ides_family:get_ancestors(TargetPid) of
        {ok, Ancestors} when Ancestors =/= [] ->
            AncestorPids = lists:filtermap(
                fun(P) ->
                    try ides_family:resolve_pid(P) of
                        Pid -> {true, Pid}
                    catch
                        _:_ -> false
                    end
                end,
                Ancestors
            ),
            case ides_family:parent_info(TargetPid) of
                {ok, Info} ->
                    KillerSiblings = killer_siblings(Info),
                    {ok,
                        ordsets:to_list(
                            ordsets:union(
                                ordsets:from_list(AncestorPids),
                                ordsets:from_list(KillerSiblings)
                            )
                        )};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, []} ->
            {error, no_ancestors};
        {error, Reason} ->
            {error, Reason}
    end.

-doc #{
    f => should_restart,
    a => 2,
    d =>
        "Return whether a terminated child `Pid` would be restarted by\n"
        "its supervisor.\n"
        "\n"
        "Rules:\n"
        "- `permanent`: always restarted\n"
        "- `transient`: restarted only on `abnormal` exit\n"
        "- `temporary`: never restarted"
}.
-spec should_restart(Pid :: pid(), Reason :: exit_reason()) -> boolean().
should_restart(Pid, ExitReason) ->
    case ides_family:get_ancestors(Pid) of
        {ok, Ancestors} when Ancestors =/= [] ->
            [Parent | _] = Ancestors,
            ParentPid = ides_family:resolve_pid(Parent),
            ChildSpecs = supervisor:which_children(ParentPid),
            {Id, _ChildPid, _Type, _Mods} = lists:keyfind(Pid, 2, ChildSpecs),
            RestartType = ides_family:get_restart_type(ParentPid, Id),
            should_restart_rule(RestartType, ExitReason);
        _ ->
            false
    end.

-doc #{
    f => affected_siblings,
    a => 1,
    d =>
        "Return the PIDs of siblings that would be killed or restarted\n"
        "if `TargetPid` dies.\n"
        "\n"
        "Depends on the parent supervisor's strategy:\n"
        "- `one_for_one`: `TargetPid` only\n"
        "- `one_for_all`: all siblings\n"
        "- `rest_for_one`: `TargetPid` and all siblings after it\n"
        "- `simple_one_for_one`: `TargetPid` only"
}.
-spec affected_siblings(TargetPid :: pid()) -> {ok, [pid()]} | {error, term()}.
affected_siblings(TargetPid) ->
    case ides_family:parent_info(TargetPid) of
        {ok, Info} ->
            Affected = affected_siblings_rule(Info),
            {ok, Affected};
        {error, Reason} ->
            {error, Reason}
    end.

%% --- Internal ---

-spec killer_siblings(Info :: ides_family:parent_info()) -> [pid()].
killer_siblings(#{sup_strategy := one_for_all, child_pids := Children, target_position := _Pos}) ->
    pids(Children);
killer_siblings(#{sup_strategy := rest_for_one, child_pids := Children, target_position := Pos}) ->
    pids(child_prefix(Children, Pos - 1));
killer_siblings(#{sup_strategy := _, child_pids := _Children, target_position := _Pos}) ->
    [].

-spec should_restart_rule(
    RestartType :: ides_family:child_restart_type(), ExitReason :: exit_reason()
) -> boolean().
should_restart_rule(permanent, _) -> true;
should_restart_rule(transient, abnormal) -> true;
should_restart_rule(transient, normal) -> false;
should_restart_rule(temporary, _) -> false.

-spec affected_siblings_rule(Info :: ides_family:parent_info()) -> [pid()].
affected_siblings_rule(#{
    sup_strategy := one_for_one, child_pids := Children, target_position := Pos
}) ->
    pids(child_sublist(Children, Pos, 1));
affected_siblings_rule(#{
    sup_strategy := one_for_all, child_pids := Children, target_position := _Pos
}) ->
    pids(Children);
affected_siblings_rule(#{
    sup_strategy := rest_for_one, child_pids := Children, target_position := Pos
}) ->
    pids(child_suffix(Children, Pos - 1));
affected_siblings_rule(#{
    sup_strategy := simple_one_for_one, child_pids := Children, target_position := Pos
}) ->
    pids(child_sublist(Children, Pos, 1)).

-spec pids(Children :: [{term(), pid()}]) -> [pid()].
pids(Children) ->
    [Pid || {_Id, Pid} <- Children].

-spec child_sublist(Children :: [{term(), pid()}], Start :: pos_integer(), Len :: pos_integer()) ->
    [{term(), pid()}].
child_sublist(Children, Start, Len) ->
    child_sublist_skip(Children, Start - 1, Len).

child_sublist_skip(Children, 0, Len) ->
    child_prefix(Children, Len);
child_sublist_skip([], _, _) ->
    [];
child_sublist_skip([_ | T], N, Len) ->
    child_sublist_skip(T, N - 1, Len).

-spec child_prefix(Children :: [{term(), pid()}], Len :: non_neg_integer()) -> [{term(), pid()}].
child_prefix(_Children, 0) -> [];
child_prefix([], _) -> [];
child_prefix([H | T], N) -> [H | child_prefix(T, N - 1)].

-spec child_suffix(Children :: [{term(), pid()}], Skip :: non_neg_integer()) -> [{term(), pid()}].
child_suffix(Children, 0) -> Children;
child_suffix([], _) -> [];
child_suffix([_ | T], N) -> child_suffix(T, N - 1).

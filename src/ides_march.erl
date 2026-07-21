-module(ides_march).

-moduledoc "Kill graph analysis and restart logic for ides.".

-export([
    kill_graph/1,
    should_restart/2,
    affected_siblings/1,
    link_info/1,
    monitor_info/1,
    kill_graph_detail/1
]).

-type exit_reason() :: normal | abnormal.
-export_type([exit_reason/0]).

-doc """
Return all PIDs that could cause `TargetPid` to be killed.

This is the set of ancestors unioned with siblings that trigger
cascade restarts under the parent supervisor's strategy:
- `one_for_one` / `simple_one_for_one`: only ancestors (no
  sibling killers)
- `one_for_all`: all siblings are killers
- `rest_for_one`: siblings at positions before the target are
  killers
""".
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
                    LinkKillers = link_killers(TargetPid),
                    MonitorKillers = monitor_killers(TargetPid),
                    {ok,
                        lists:usort(
                            AncestorPids ++
                                KillerSiblings ++
                                LinkKillers ++
                                MonitorKillers
                        )};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, []} ->
            {error, no_ancestors};
        {error, Reason} ->
            {error, Reason}
    end.

-doc """
Return whether a terminated child `Pid` would be restarted by
its supervisor.

Rules:
- `permanent`: always restarted
- `transient`: restarted only on `abnormal` exit
- `temporary`: never restarted
""".
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

-doc """
Return the PIDs of siblings that would be killed or restarted
if `TargetPid` dies.

Depends on the parent supervisor's strategy:
- `one_for_one`: `TargetPid` only
- `one_for_all`: all siblings
- `rest_for_one`: `TargetPid` and all siblings after it
- `simple_one_for_one`: `TargetPid` only
""".
-spec affected_siblings(TargetPid :: pid()) -> {ok, [pid()]} | {error, term()}.
affected_siblings(TargetPid) ->
    case ides_family:parent_info(TargetPid) of
        {ok, Info} ->
            Affected = affected_siblings_rule(Info),
            {ok, Affected};
        {error, Reason} ->
            {error, Reason}
    end.

-doc """
Return link information for the given process.

Reports which processes are linked to `Pid` and whether
`Pid` traps exits. Linked processes are potential killers
if `traps_exits` is `false`.
""".
-spec link_info(Pid :: pid()) -> {ok, ides_family:link_info()} | {error, term()}.
link_info(Pid) ->
    case erlang:process_info(Pid, [links, trap_exit, status]) of
        [{links, Links}, {trap_exit, Traps}, {status, _}] ->
            {ok, #{
                links => Links -- [Pid],
                traps_exits => Traps
            }};
        undefined ->
            {error, process_not_alive};
        Other ->
            {error, {unexpected_process_info, Other}}
    end.

-doc """
Return monitor information for the given process.

Reports which processes `Pid` is monitoring and which
processes are monitoring `Pid`. Monitored processes are
potential killers if `Pid` doesn't handle DOWN messages.
""".
-spec monitor_info(Pid :: pid()) -> {ok, ides_family:monitor_info()} | {error, term()}.
monitor_info(Pid) ->
    case erlang:process_info(Pid, [monitors, monitored_by, status]) of
        [{monitors, Monitors}, {monitored_by, MonitoredBy}, {status, _}] ->
            MonitorPids = [MPid || {process, MPid} <- Monitors],
            {ok, #{
                monitors => MonitorPids,
                monitored_by => MonitoredBy
            }};
        undefined ->
            {error, process_not_alive};
        Other ->
            {error, {unexpected_process_info, Other}}
    end.

-doc """
Return the kill graph with each entry tagged by its kill mechanism:
- `ancestor` — supervisor ancestor
- `sibling` — sibling via supervisor strategy
- `link` — linked process (relevant if target doesn't trap exits)
- `monitor` — monitored process (relevant if target doesn't handle DOWN)
""".
-spec kill_graph_detail(TargetPid :: pid()) -> {ok, [ides_family:kill_source()]} | {error, term()}.
kill_graph_detail(TargetPid) ->
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
                    SiblingKillers = killer_siblings(Info),
                    LinkKillers = link_killers(TargetPid),
                    MonitorKillers = monitor_killers(TargetPid),
                    Tagged =
                        [{ancestor, P} || P <- AncestorPids] ++
                            [{sibling, P} || P <- SiblingKillers] ++
                            [{link, P} || P <- LinkKillers] ++
                            [{monitor, P} || P <- MonitorKillers],
                    {ok, Tagged};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, []} ->
            {error, no_ancestors};
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

-spec link_killers(Pid :: pid()) -> [pid()].
link_killers(Pid) ->
    case link_info(Pid) of
        {ok, #{traps_exits := true}} ->
            [];
        {ok, #{links := Links, traps_exits := false}} ->
            Links;
        _ ->
            []
    end.

-spec monitor_killers(Pid :: pid()) -> [pid()].
monitor_killers(Pid) ->
    case monitor_info(Pid) of
        {ok, #{monitors := Monitors}} ->
            Monitors;
        _ ->
            []
    end.

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

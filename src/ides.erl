-module(ides).

%% @doc Beware the Ides of March — find the supervisors and siblings that could
%% kill your Erlang process.
%%
%% Given any PID, this module shows:
%% - **Ancestors**: the chain of supervisors above the process
%% - **Siblings**: all children of the same supervisor
%% - **Kill graph**: every process that could cause this PID to be killed
%% - **Restart logic**: whether a terminated child will be restarted
%% - **Affected siblings**: which siblings a supervisor would kill/restart if
%%   this PID dies
%%
%% Uses OTP primitives: `erlang:process_info/2` for `$ancestors`,
%% `supervisor:which_children/1`, and `proc_lib:translate_initial_call/1`.

-export([ancestors/1, format/2, print/2,
         kill_graph/1, should_restart/2, affected_siblings/1]).

%% @doc Restart strategy of a supervisor.
-type supervisor_strategy() :: one_for_one
                             | one_for_all
                             | rest_for_one
                             | simple_one_for_one.

%% @doc Restart type of a child process.
-type child_restart_type() :: permanent
                             | transient
                             | temporary.

%% @doc Exit reason for `should_restart/2`.
-type exit_reason() :: normal | abnormal.

%% @doc A worker (leaf) process.
%% Includes its `restart_type` as defined in the parent supervisor's child spec.
-type child_process() :: #{
    name         := string(),
    pid          := pid(),
    type         := worker,
    restart_type := child_restart_type()
}.

%% @doc A supervisor process. Contains its `strategy` and ordered list of
%% `children`. When this supervisor is also a child of another supervisor,
%% `restart_type` is present.
-type supervisor_process() :: #{
    name         := string(),
    pid          := pid(),
    type         := supervisor,
    strategy     := supervisor_strategy(),
    restart_type => child_restart_type(),
    children     := [process()]
}.

%% @doc A process in the supervision tree: a supervisor or a worker.
-type process() :: supervisor_process() | child_process().

-export_type([process/0, supervisor_process/0, child_process/0,
              supervisor_strategy/0, child_restart_type/0, exit_reason/0]).

%% @doc Walk the supervision tree from the topmost ancestor down to `TargetPid`.
%% Returns the tree including the ancestor chain and all siblings at each level.
-spec ancestors(TargetPid :: pid()) -> {ok, process()} | {error, term()}.
ancestors(TargetPid) ->
    case get_ancestors(TargetPid) of
        {ok, Ancestors} when Ancestors =/= [] ->
            case find_root_supervisor(Ancestors) of
                {ok, RootPid} ->
                    walk_down(RootPid, TargetPid);
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, []} ->
            {error, no_ancestors};
        {error, Reason} ->
            {error, Reason}
    end.

-spec find_root_supervisor(Ancestors :: [term()]) -> {ok, pid()} | {error, term()}.
find_root_supervisor(Ancestors) ->
    do_find_root_supervisor(lists:reverse(Ancestors)).

do_find_root_supervisor([]) ->
    {error, no_supervisor_ancestor};
do_find_root_supervisor([Pid | Rest]) ->
    Resolved = resolve_pid(Pid),
    case is_supervisor_ancestor(Resolved) of
        true -> {ok, Resolved};
        false -> do_find_root_supervisor(Rest)
    end.

-spec resolve_pid(Pid :: term()) -> pid().
resolve_pid(Pid) when is_pid(Pid) ->
    Pid;
resolve_pid(Pid) when is_atom(Pid) ->
    case whereis(Pid) of
        undefined ->
            error({unresolved_registered_name, Pid});
        Pid2 when is_pid(Pid2) ->
            Pid2
    end;
resolve_pid(Pid) ->
    error({not_a_pid, Pid}).

-spec is_supervisor_ancestor(Pid :: pid() | atom()) -> boolean().
is_supervisor_ancestor(Pid) when Pid =:= self() ->
    false;
is_supervisor_ancestor(Pid) when is_pid(Pid) ->
    case erlang:process_info(Pid, [initial_call, dictionary]) of
        [{initial_call, {supervisor, _, 1}} | _] ->
            true;
        [{initial_call, {proc_lib, init_p, 5}}, {dictionary, Dict}] ->
            case proplists:get_value('$initial_call', Dict) of
                {supervisor, _, 1} -> true;
                _ -> false
            end;
        _ ->
            false
    end;
is_supervisor_ancestor(_) ->
    false.

-spec get_ancestors(Pid :: pid()) -> {ok, [term()]} | {error, term()}.
get_ancestors(Pid) ->
    case erlang:process_info(Pid, dictionary) of
        {dictionary, Dict} ->
            case proplists:get_value('$ancestors', Dict) of
                undefined ->
                    {error, no_ancestors};
                Ancestors when is_list(Ancestors) ->
                    {ok, Ancestors}
            end;
        undefined ->
            {error, process_not_alive};
        _ ->
            {error, no_dictionary}
    end.

-spec walk_down(RootPid :: pid() | atom(), TargetPid :: pid()) -> {ok, process()} | {error, term()}.
walk_down(RootPid, TargetPid) when is_atom(RootPid) ->
    case whereis(RootPid) of
        undefined ->
            {error, {process_not_alive, RootPid}};
        Pid when is_pid(Pid) ->
            walk_down(Pid, TargetPid)
    end;
walk_down(RootPid, TargetPid) ->
    case erlang:process_info(RootPid, [status]) of
        undefined ->
            {error, {process_not_alive, RootPid}};
        _ ->
            try walk_supervisor(RootPid, TargetPid) of
                Tree -> {ok, Tree}
            catch
                throw:Reason -> {error, Reason};
                error:Reason -> {error, Reason};
                exit:Reason -> {error, {exit, Reason}}
            end
    end.

-spec walk_supervisor(SupPid :: pid(), TargetPid :: pid()) -> process().
walk_supervisor(SupPid, TargetPid) ->
    Name = get_name(SupPid),
    Strategy = get_strategy(SupPid),
    ChildList = supervisor:which_children(SupPid),
    Children = lists:filtermap(fun(Child) -> walk_child_maybe(SupPid, Child, TargetPid) end, ChildList),
    #{name => Name, pid => SupPid, type => supervisor,
      strategy => Strategy, children => Children}.

-spec walk_child_maybe(SupPid :: pid(),
                       {Id :: term(), Child :: pid() | undefined | restarting, worker | supervisor, term()},
                       TargetPid :: pid())
                      -> {true, process()} | false.
walk_child_maybe(SupPid, {Id, ChildPid, Type, Modules}, TargetPid) when is_pid(ChildPid) ->
    {true, walk_child(SupPid, {Id, ChildPid, Type, Modules}, TargetPid)};
walk_child_maybe(_SupPid, {_Id, _ChildPid, _Type, _Modules}, _TargetPid) ->
    false.

-spec walk_child(SupPid :: pid(),
                 {Id :: term(), ChildPid :: pid(), worker | supervisor, term()},
                 TargetPid :: pid())
               -> process().
walk_child(SupPid, {Id, ChildPid, worker, _Modules}, _TargetPid) when is_pid(ChildPid) ->
    Name = get_name(ChildPid),
    RestartType = get_restart_type(SupPid, Id),
    #{name => Name, pid => ChildPid, type => worker, restart_type => RestartType};
walk_child(SupPid, {Id, ChildPid, supervisor, _Modules}, TargetPid) when is_pid(ChildPid) ->
    RestartType = get_restart_type(SupPid, Id),
    ChildTree = walk_supervisor(ChildPid, TargetPid),
    ChildTree#{restart_type => RestartType};
walk_child(_SupPid, {Id, _ChildPid, _Type, _Modules}, _TargetPid) ->
    throw({unexpected_child_state, Id, _ChildPid}).

-spec get_name(Pid :: pid()) -> string().
get_name(Pid) ->
    case erlang:process_info(Pid, registered_name) of
        {registered_name, Name} when is_atom(Name) ->
            atom_to_list(Name);
        _ ->
            case proc_lib:translate_initial_call(Pid) of
                {proc_lib, init_p, 5} ->
                    case erlang:process_info(Pid, initial_call) of
                        {initial_call, {M, F, A}} ->
                            lists:flatten(io_lib:format("~s:~s/~B", [M, F, A]));
                        _ ->
                            pid_to_list(Pid)
                    end;
                {M, F, A} ->
                    lists:flatten(io_lib:format("~s:~s/~B", [M, F, A]));
                _Other ->
                    pid_to_list(Pid)
            end
    end.

-spec get_strategy(SupPid :: pid()) -> supervisor_strategy().
get_strategy(SupPid) ->
    try sys:get_state(SupPid) of
        State when is_tuple(State) ->
            strategy_from_state(State)
    catch
        _:_ -> one_for_one
    end.

-spec strategy_from_state(State :: tuple()) -> supervisor_strategy().
strategy_from_state(State) ->
    Second = element(2, State),
    case Second of
        {_Kind, _Name} when tuple_size(State) >= 3 ->
            case element(3, State) of
                S when is_atom(S) -> map_strategy(S);
                _ -> one_for_one
            end;
        S when is_atom(S) -> map_strategy(S);
        S when is_map(S) -> one_for_one;
        _ -> one_for_one
    end.

-spec map_strategy(atom()) -> supervisor_strategy().
map_strategy(S) when S =:= one_for_one;
                     S =:= one_for_all;
                     S =:= rest_for_one;
                     S =:= simple_one_for_one ->
    S;
map_strategy(_) ->
    one_for_one.

-spec get_restart_type(SupPid :: pid(), Id :: term()) -> child_restart_type().
get_restart_type(SupPid, Id) ->
    case supervisor:get_childspec(SupPid, Id) of
        {ok, #{restart := RestartType}} ->
            RestartType;
        {ok, {Id, _StartFunc, RestartType, _Shutdown, _Type, _Modules}} ->
            RestartType;
        _ ->
            permanent
    end.

%% @doc Render the supervision tree as indented ASCII text.
%% The target process is marked with `*`. Indentation is 4 spaces per level.
%%
%% Rendering rules:
%% - Root supervisor: `name (strategy)`
%% - Supervisor child: `name (strategy, restart_type)`
%% - Worker child: `name (restart_type)`
%% - Target process: prefixed with `* `
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

-spec prefix(TargetPid :: pid(), Pid :: pid(), Depth :: non_neg_integer()) -> [string()].
prefix(_TargetPid, _Pid, 0) -> [""];
prefix(TargetPid, Pid, Depth) ->
    Indent = spaces(Depth * 4 - 2),
    [Indent, marker(TargetPid, Pid)].

-spec spaces(non_neg_integer()) -> string().
spaces(0) -> "";
spaces(N) -> [$\s | spaces(N - 1)].

-spec marker(TargetPid :: pid(), Pid :: pid()) -> string().
marker(TargetPid, TargetPid) -> "* ";
marker(_TargetPid, _Pid)      -> "  ".

%% @doc Like `format/2` but writes the rendered tree to stdout.
-spec print(TargetPid :: pid(), Tree :: process()) -> ok.
print(TargetPid, Tree) ->
    io:put_chars(format(TargetPid, Tree)).

%% --- TLA+ properties ---

-type parent_info() :: #{
    sup_pid        := pid(),
    sup_strategy   := supervisor_strategy(),
    child_pids     := [{term(), pid()}],
    target_position => pos_integer()
}.

%% @doc Return all PIDs that could cause `TargetPid` to be killed.
%%
%% This is the set of ancestors unioned with siblings that trigger cascade
%% restarts under the parent supervisor's strategy:
%% - `one_for_one` / `simple_one_for_one`: only ancestors (no sibling killers)
%% - `one_for_all`: all siblings are killers
%% - `rest_for_one`: siblings at positions before the target are killers
-spec kill_graph(TargetPid :: pid()) -> {ok, [pid()]} | {error, term()}.
kill_graph(TargetPid) ->
    case get_ancestors(TargetPid) of
        {ok, Ancestors} when Ancestors =/= [] ->
            AncestorPids = lists:filtermap(
                fun(P) ->
                    try resolve_pid(P) of
                        Pid -> {true, Pid}
                    catch _:_ -> false
                    end
                end, Ancestors),
            case parent_info(TargetPid) of
                {ok, Info} ->
                    KillerSiblings = killer_siblings(Info),
                    {ok, ordsets:to_list(ordsets:union(
                        ordsets:from_list(AncestorPids),
                        ordsets:from_list(KillerSiblings)))};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, []} ->
            {error, no_ancestors};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Return whether a terminated child `Pid` would be restarted by its supervisor.
%%
%% Rules:
%% - `permanent`: always restarted
%% - `transient`: restarted only on `abnormal` exit
%% - `temporary`: never restarted
-spec should_restart(Pid :: pid(), Reason :: exit_reason()) -> boolean().
should_restart(Pid, ExitReason) ->
    case get_ancestors(Pid) of
        {ok, Ancestors} when Ancestors =/= [] ->
            [Parent | _] = Ancestors,
            ParentPid = resolve_pid(Parent),
            ChildSpecs = supervisor:which_children(ParentPid),
            {Id, _ChildPid, _Type, _Mods} = lists:keyfind(Pid, 2, ChildSpecs),
            RestartType = get_restart_type(ParentPid, Id),
            should_restart_rule(RestartType, ExitReason);
        _ ->
            false
    end.

%% @doc Return the PIDs of siblings that would be killed or restarted if
%% `TargetPid` dies.
%%
%% Depends on the parent supervisor's strategy:
%% - `one_for_one`: `TargetPid` only
%% - `one_for_all`: all siblings
%% - `rest_for_one`: `TargetPid` and all siblings after it
%% - `simple_one_for_one`: `TargetPid` only
-spec affected_siblings(TargetPid :: pid()) -> {ok, [pid()]} | {error, term()}.
affected_siblings(TargetPid) ->
    case parent_info(TargetPid) of
        {ok, Info} ->
            Affected = affected_siblings_rule(Info),
            {ok, Affected};
        {error, Reason} ->
            {error, Reason}
    end.

%% --- Parent info extraction ---

-spec parent_info(Pid :: pid()) -> {ok, parent_info()} | {error, term()}.
parent_info(Pid) ->
    case get_ancestors(Pid) of
        {ok, Ancestors} when Ancestors =/= [] ->
            [Parent | _] = Ancestors,
            ParentPid = resolve_pid(Parent),
            Strategy = get_strategy(ParentPid),
            Children = supervisor:which_children(ParentPid),
            ChildPids = child_pids(Children),
            Pos = child_position(Pid, ChildPids),
            {ok, #{
                sup_pid => ParentPid,
                sup_strategy => Strategy,
                child_pids => ChildPids,
                target_position => Pos
            }};
        _ ->
            {error, no_ancestors}
    end.

-spec child_position(Pid :: pid(), Children :: [{term(), pid()}]) -> pos_integer().
child_position(Pid, Children) ->
    child_position(Pid, Children, 1).

child_position(Pid, [{_, Pid} | _], N) -> N;
child_position(Pid, [_ | Rest], N) -> child_position(Pid, Rest, N + 1);
child_position(_Pid, [], _N) -> 1.

-spec child_pids(Children :: [term()]) -> [{term(), pid()}].
child_pids(Children) ->
    [{Id, Pid} || {Id, Pid, _Type, _Mods} <- Children, is_pid(Pid)].

%% --- TLA+ derived rules ---

-spec killer_siblings(Info :: parent_info()) -> [pid()].
killer_siblings(#{sup_strategy := one_for_all, child_pids := Children, target_position := _Pos}) ->
    pids(Children);
killer_siblings(#{sup_strategy := rest_for_one, child_pids := Children, target_position := Pos}) ->
    pids(child_prefix(Children, Pos - 1));
killer_siblings(#{sup_strategy := _, child_pids := _Children, target_position := _Pos}) ->
    [].

-spec should_restart_rule(RestartType :: child_restart_type(), ExitReason :: exit_reason()) -> boolean().
should_restart_rule(permanent, _) -> true;
should_restart_rule(transient, abnormal) -> true;
should_restart_rule(transient, normal) -> false;
should_restart_rule(temporary, _) -> false.

-spec affected_siblings_rule(Info :: parent_info()) -> [pid()].
affected_siblings_rule(#{sup_strategy := one_for_one, child_pids := Children, target_position := Pos}) ->
    pids(child_sublist(Children, Pos, 1));
affected_siblings_rule(#{sup_strategy := one_for_all, child_pids := Children, target_position := _Pos}) ->
    pids(Children);
affected_siblings_rule(#{sup_strategy := rest_for_one, child_pids := Children, target_position := Pos}) ->
    pids(child_suffix(Children, Pos - 1));
affected_siblings_rule(#{sup_strategy := simple_one_for_one, child_pids := Children, target_position := Pos}) ->
    pids(child_sublist(Children, Pos, 1)).

-spec pids(Children :: [{term(), pid()}]) -> [pid()].
pids(Children) ->
    [Pid || {_Id, Pid} <- Children].

-spec child_sublist(Children :: [{term(), pid()}], Start :: pos_integer(), Len :: pos_integer()) -> [{term(), pid()}].
child_sublist(Children, Start, Len) ->
    child_sublist_skip(Children, Start - 1, Len).

child_sublist_skip(Children, 0, Len) ->
    child_prefix(Children, Len);
child_sublist_skip([], _, _) -> [];
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

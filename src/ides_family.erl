-module(ides_family).

-doc "Type definitions and tree-walking primitives for ides.".

%% --- Types ---

-doc #{f => supervisor_strategy, d => "Restart strategy of a supervisor."}.
-type supervisor_strategy() ::
    one_for_one
    | one_for_all
    | rest_for_one
    | simple_one_for_one.

-doc #{f => child_restart_type, d => "Restart type of a child process."}.
-type child_restart_type() ::
    permanent
    | transient
    | temporary.

-doc #{
    f => child_process,
    d =>
        "A worker (leaf) process. Includes its `restart_type` as defined\n"
        "in the parent supervisor's child spec."
}.
-type child_process() :: #{
    name := string(),
    pid := pid(),
    type := worker,
    restart_type := child_restart_type()
}.

-doc #{
    f => supervisor_process,
    d =>
        "A supervisor process. Contains its `strategy` and ordered list\n"
        "of `children`. When this supervisor is also a child of another\n"
        "supervisor, `restart_type` is present."
}.
-type supervisor_process() :: #{
    name := string(),
    pid := pid(),
    type := supervisor,
    strategy := supervisor_strategy(),
    restart_type => child_restart_type(),
    children := [process()]
}.

-doc #{f => process, d => "A process in the supervision tree: a supervisor or a worker."}.
-type process() :: supervisor_process() | child_process().

-type parent_info() :: #{
    sup_pid := pid(),
    sup_strategy := supervisor_strategy(),
    child_pids := [{term(), pid()}],
    target_position => pos_integer()
}.

-export_type([
    process/0,
    supervisor_process/0,
    child_process/0,
    supervisor_strategy/0,
    child_restart_type/0,
    parent_info/0
]).

%% --- API ---

-export([ancestors/1, get_ancestors/1, parent_info/1]).

%% Internal helpers exported for sibling modules
-export([
    resolve_pid/1,
    get_name/1,
    get_strategy/1,
    get_restart_type/2,
    child_pids/1,
    child_position/2
]).

%% --- Functions ---

-doc #{
    f => ancestors,
    a => 1,
    d =>
        "Walk the supervision tree from the topmost ancestor down to\n"
        "`TargetPid`. Returns the tree including the ancestor chain and\n"
        "all siblings at each level."
}.
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
    Children = lists:filtermap(
        fun(Child) -> walk_child_maybe(SupPid, Child, TargetPid) end, ChildList
    ),
    #{
        name => Name,
        pid => SupPid,
        type => supervisor,
        strategy => Strategy,
        children => Children
    }.

-spec walk_child_maybe(
    SupPid :: pid(),
    {Id :: term(), Child :: pid() | undefined | restarting, worker | supervisor, term()},
    TargetPid :: pid()
) ->
    {true, process()} | false.
walk_child_maybe(SupPid, {Id, ChildPid, Type, Modules}, TargetPid) when is_pid(ChildPid) ->
    {true, walk_child(SupPid, {Id, ChildPid, Type, Modules}, TargetPid)};
walk_child_maybe(_SupPid, {_Id, _ChildPid, _Type, _Modules}, _TargetPid) ->
    false.

-spec walk_child(
    SupPid :: pid(),
    {Id :: term(), ChildPid :: pid(), worker | supervisor, term()},
    TargetPid :: pid()
) ->
    process().
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
        _ ->
            one_for_one
    end.

-spec map_strategy(atom()) -> supervisor_strategy().
map_strategy(S) when
    S =:= one_for_one;
    S =:= one_for_all;
    S =:= rest_for_one;
    S =:= simple_one_for_one
->
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

%% --- Parent info ---

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

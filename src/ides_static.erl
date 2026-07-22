-module(ides_static).

-export([
    supervisor_tree/1,
    kill_graph/2,
    ancestors/2,
    siblings/2,
    intensity_info/2,
    format/2,
    print/2,
    find_process_by_name/2
]).

-export_type([
    worker_process/0,
    supervisor_process/0,
    static_process/0,
    intensity_info/0,
    kill_source/0,
    static_error/0,
    static_warning/0
]).

-type worker_process() :: #{
    name := string(),
    module := module(),
    type := worker,
    restart_type := ides:child_restart_type()
}.

-type supervisor_process() :: #{
    name := string(),
    module := module(),
    type := supervisor,
    strategy := ides:supervisor_strategy(),
    restart_type => ides:child_restart_type(),
    children := [static_process()],
    intensity := intensity_info()
}.

-type static_process() :: supervisor_process() | worker_process().

-type intensity_info() :: #{
    max_restarts := non_neg_integer(),
    max_period := non_neg_integer()
}.

-type kill_source() :: {ancestor, module()} | {sibling, module()}.

-type static_error() :: {missing_beam, module()}
                      | {no_debug_info, module()}
                      | {not_a_supervisor, module()}
                      | {dynamic_child_spec, module()}
                      | {unresolvable_module, module()}.

-type static_warning() :: {unresolvable_module, module()}
                        | {dynamic_child_spec, module()}
                        | {missing_behaviour, module()}.

-doc "Build the static supervision tree from BEAM files."
      "Returns tree roots and any warnings (unresolvable modules, dynamic children).".
-spec supervisor_tree([file:filename()]) ->
    {ok, #{tree := [static_process()], warnings := [static_warning()]}} | {error, static_error()}.

supervisor_tree(BeamPaths) ->
    {ok, BeamMap} = ides_static_beam:load_beams(BeamPaths),
    Supervisors = maps:filter(fun(_M, Info) -> ides_static_beam:is_supervisor(Info) end, BeamMap),
    {RootTrees, Warnings} = build_trees(Supervisors, BeamMap),
    {ok, #{tree => RootTrees, warnings => Warnings}}.

build_trees(Supervisors, BeamMap) ->
    {AllTrees, AllWarnings} = maps:fold(
        fun(Module, Info, {TreesAcc, WarnAcc}) ->
            case ides_static_parse:parse_init(Info) of
                {ok, SupFlags, ChildSpecs} ->
                    {Children, ChildWarnings} = build_children(ChildSpecs, BeamMap),
                    Tree = #{
                        name => atom_to_list(Module),
                        module => Module,
                        type => supervisor,
                        strategy => maps:get(strategy, SupFlags),
                        children => Children,
                        intensity => #{
                            max_restarts => maps:get(intensity, SupFlags),
                            max_period => maps:get(period, SupFlags)
                        }
                    },
                    {[Tree | TreesAcc], WarnAcc ++ ChildWarnings};
                {error, _} ->
                    {TreesAcc, WarnAcc}
            end
        end,
        {[], []},
        Supervisors
    ),
    %% Only return root supervisors (not referenced as children of others)
    AllChildModules = collect_child_modules(AllTrees),
    RootTrees = [T || T <- AllTrees, not lists:member(maps:get(module, T), AllChildModules)],
    {RootTrees, AllWarnings}.

collect_child_modules(Trees) ->
    lists:flatmap(fun collect_modules/1, Trees).

collect_modules(#{children := Children}) ->
    [maps:get(module, C) || C <- Children] ++
        lists:flatmap(fun collect_modules/1, Children);
collect_modules(_) ->
    [].

build_children(ChildSpecs, BeamMap) ->
    lists:foldl(
        fun(Child, {KidsAcc, WarnAcc}) ->
            {Kid, Warns} = build_child(Child, BeamMap),
            {KidsAcc ++ [Kid], WarnAcc ++ Warns}
        end,
        {[], []},
        ChildSpecs
    ).

build_child(Child, BeamMap) ->
    {M, _F, _A} = maps:get(start, Child),
    case maps:get(type, Child) of
        supervisor ->
            case maps:find(M, BeamMap) of
                {ok, Info} ->
                    case ides_static_parse:parse_init(Info) of
                        {ok, SupFlags, ChildSpecs} ->
                            {Children, ChildWarnings} = build_children(ChildSpecs, BeamMap),
                            Warns = child_warnings(SupFlags, M, ChildWarnings),
                            Result = #{
                                name => atom_to_list(maps:get(id, Child)),
                                module => M,
                                type => supervisor,
                                strategy => maps:get(strategy, SupFlags),
                                restart_type => maps:get(restart, Child),
                                children => Children,
                                intensity => #{
                                    max_restarts => maps:get(intensity, SupFlags),
                                    max_period => maps:get(period, SupFlags)
                                }
                            },
                            {Result, Warns};
                        {error, _} ->
                            {#{
                                name => atom_to_list(maps:get(id, Child)),
                                module => M,
                                type => worker,
                                restart_type => maps:get(restart, Child)
                            }, []}
                    end;
                error ->
                    {#{
                        name => atom_to_list(maps:get(id, Child)),
                        module => M,
                        type => worker,
                        restart_type => maps:get(restart, Child)
                    }, [{unresolvable_module, M}]}
            end;
        worker ->
            Warns = case maps:find(M, BeamMap) of
                {ok, _} -> [];
                error -> [{unresolvable_module, M}]
            end,
            {#{
                name => atom_to_list(maps:get(id, Child)),
                module => M,
                type => worker,
                restart_type => maps:get(restart, Child)
            }, Warns}
    end.

child_warnings(SupFlags, M, ChildWarnings) ->
    case maps:get(strategy, SupFlags) of
        simple_one_for_one -> [{dynamic_child_spec, M} | ChildWarnings];
        _ -> ChildWarnings
    end.

-doc "Return restart intensity policy for a supervisor module.".
-spec intensity_info(module(), [file:filename()]) ->
    {ok, intensity_info()} | {error, static_error()}.

intensity_info(Module, BeamPaths) ->
    {ok, BeamMap} = ides_static_beam:load_beams(BeamPaths),
    case maps:find(Module, BeamMap) of
        {ok, Info} ->
            case ides_static_beam:is_supervisor(Info) of
                true ->
                    case ides_static_parse:parse_init(Info) of
                        {ok, SupFlags, _ChildSpecs} ->
                            {ok, #{
                                max_restarts => maps:get(intensity, SupFlags),
                                max_period => maps:get(period, SupFlags)
                            }};
                        {error, _Reason} = Err ->
                            Err
                    end;
                false ->
                    {error, {not_a_supervisor, Module}}
            end;
        error ->
            {error, {missing_beam, Module}}
    end.

-doc "Return all modules that could cause the target module's process to be killed.".
-spec kill_graph(module(), [file:filename()]) ->
    {ok, [module()]} | {error, static_error()}.

kill_graph(Module, BeamPaths) ->
    case supervisor_tree(BeamPaths) of
        {ok, #{tree := Trees}} ->
            Killers = find_killers(Module, Trees),
            {ok, Killers};
        {error, _} = Err ->
            Err
    end.

find_killers(Module, Trees) ->
    lists:usort(find_killers_in_trees(Module, Trees)).

find_killers_in_trees(Module, Trees) ->
    lists:flatmap(fun(Tree) -> find_killers_in_node(Module, Tree, []) end, Trees).

find_killers_in_node(Module, #{type := supervisor, children := Children} = Sup, Ancestors) ->
    SupModule = maps:get(module, Sup),
    case has_child(Module, Children) of
        true ->
            AncestorModules = [maps:get(module, A) || A <- Ancestors],
            Strategy = maps:get(strategy, Sup),
            SiblingKillers = killer_siblings_for(Strategy, Module, Children),
            [SupModule | AncestorModules] ++ SiblingKillers ++
                child_killers(Module, Children, [Sup | Ancestors]);
        false ->
            child_killers(Module, Children, [Sup | Ancestors])
    end;
find_killers_in_node(_Module, _Node, _Ancestors) ->
    [].

child_killers(Module, Children, Ancestors) ->
    lists:flatmap(
        fun(C) -> find_killers_in_node(Module, C, Ancestors) end,
        Children
    ).

killer_siblings_for(one_for_all, Module, Children) ->
    child_modules_except(Module, Children);
killer_siblings_for(rest_for_one, Module, Children) ->
    {Before, _} = lists:splitwith(
        fun(C) -> maps:get(module, C) =/= Module end,
        Children
    ),
    [maps:get(module, C) || C <- Before];
killer_siblings_for(_, _Module, _Children) ->
    [].

has_child(Module, Children) ->
    lists:any(fun(C) -> maps:get(module, C) =:= Module end, Children).

child_modules_except(Module, Children) ->
    [maps:get(module, C) || C <- Children, maps:get(module, C) =/= Module].

-doc "Return the ancestor supervisor chain for a module, from root to direct parent.".
-spec ancestors(module(), [file:filename()]) ->
    {ok, [module()]} | {error, static_error()}.

ancestors(Module, BeamPaths) ->
    case supervisor_tree(BeamPaths) of
        {ok, #{tree := Trees}} ->
            case find_ancestors(Module, Trees) of
                [] -> {error, not_found};
                Path -> {ok, Path}
            end;
        {error, _} = Err ->
            Err
    end.

find_ancestors(Module, Trees) ->
    lists:flatmap(fun(T) -> find_ancestors_path(Module, T) end, Trees).

find_ancestors_path(Module, #{type := supervisor, module := Mod, children := Children}) ->
    case has_child(Module, Children) of
        true ->
            [Mod];
        false ->
            case lists:flatmap(fun(C) -> find_ancestors_path(Module, C) end, Children) of
                [] -> [];
                [_ | _] = InnerPath -> [Mod | InnerPath]
            end
    end;
find_ancestors_path(_Module, _Node) ->
    [].

-doc "Return sibling modules (other children of the same parent supervisor).".
-spec siblings(module(), [file:filename()]) ->
    {ok, [module()]} | {error, static_error()}.

siblings(Module, BeamPaths) ->
    case supervisor_tree(BeamPaths) of
        {ok, #{tree := Trees}} ->
            {ok, find_siblings(Module, Trees)};
        {error, _} = Err ->
            Err
    end.

find_siblings(Module, Trees) ->
    lists:usort(find_siblings_in_trees(Module, Trees)).

find_siblings_in_trees(Module, [#{children := Children} | _] = Trees) ->
    case has_child(Module, Children) of
        true ->
            child_modules_except(Module, Children);
        false ->
            lists:flatmap(
                fun(#{children := Cs}) -> find_siblings_in_trees(Module, Cs) end,
                Trees
            )
    end;
find_siblings_in_trees(_Module, _Nodes) ->
    [].

-doc "Render the supervision tree as indented ASCII, marking the target with `*`."
      "Accepts the result map from `supervisor_tree/1` or a plain list of trees.".
-spec format(module(), #{tree := [static_process()]} | [static_process()]) -> iolist().

format(Module, #{tree := Trees}) ->
    [format_node(Module, T, 0) || T <- Trees];
format(Module, Trees) ->
    [format_node(Module, T, 0) || T <- Trees].

format_node(
    Module,
    #{type := supervisor, strategy := Strategy, children := Children} = Node,
    Depth
) ->
    Name = maps:get(name, Node, atom_to_list(maps:get(module, Node))),
    Anno = case maps:find(restart_type, Node) of
        {ok, Restart} -> [" (", atom_to_list(Strategy), ", ", atom_to_list(Restart), ")"];
        error -> [" (", atom_to_list(Strategy), ")"]
    end,
    Prefix = format_prefix(Module, Node, Depth),
    [
        Prefix, Name, Anno, "\n"
        | [format_node(Module, C, Depth + 1) || C <- Children]
    ];
format_node(Module, #{type := worker, restart_type := Restart} = Node, Depth) ->
    Name = maps:get(name, Node, atom_to_list(maps:get(module, Node))),
    Prefix = format_prefix(Module, Node, Depth),
    [Prefix, Name, " (", atom_to_list(Restart), ")\n"].

format_prefix(_Module, _Node, 0) ->
    "";
format_prefix(Module, #{module := Module}, Depth) ->
    lists:duplicate(Depth * 4 - 2, $\s) ++ "* ";
format_prefix(_Module, _Node, Depth) ->
    lists:duplicate(Depth * 4 - 2, $\s) ++ "  ".

-doc "Like `format/2` but writes to stdout."
      "Accepts the result map from `supervisor_tree/1` or a plain list of trees.".
-spec print(module(), #{tree := [static_process()]} | [static_process()]) -> ok.

print(Module, Trees) ->
    io:format("~s", [format(Module, Trees)]).

-doc "Look up a module by its registered process name in the tree.".
-spec find_process_by_name(string(), [static_process()]) -> {ok, module()} | {error, not_found}.

find_process_by_name(Name, Trees) ->
    find_by_name(Name, Trees).

find_by_name(Name, [#{name := Name, module := Mod} | _]) ->
    {ok, Mod};
find_by_name(Name, [#{children := Children} | Rest]) ->
    case find_by_name(Name, Children) of
        {ok, Mod} -> {ok, Mod};
        {error, not_found} -> find_by_name(Name, Rest)
    end;
find_by_name(Name, [_ | Rest]) ->
    find_by_name(Name, Rest);
find_by_name(_, []) ->
    {error, not_found}.

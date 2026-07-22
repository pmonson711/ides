-module(ides_static_parse).

-export([parse_init/1]).

-type sup_flags() :: #{
    strategy := ides:supervisor_strategy(),
    intensity := non_neg_integer(),
    period := non_neg_integer()
}.

-type child_spec() :: #{
    id := atom(),
    start := {module(), atom(), [term()]},
    restart := ides:child_restart_type(),
    type := worker | supervisor
}.

-export_type([sup_flags/0, child_spec/0]).

-spec parse_init(ides_static_beam:beam_info()) ->
    {ok, sup_flags(), [child_spec()]} | {error, term()}.

parse_init(#{abstract_code := Abstr}) ->
    case find_init_function(Abstr) of
        {ok, Clause} ->
            parse_init_clause(Clause);
        error ->
            {error, no_init_function}
    end;
parse_init(_) ->
    {error, no_abstract_code}.

find_init_function(Abstr) ->
    case [F || {function, _, init, 1, _} = F <- Abstr] of
        [Func] ->
            {function, _, _, _, [Clause | _]} = Func,
            {ok, Clause};
        [] ->
            error
    end.

parse_init_clause({clause, _Line, _Args, _Guards, Body}) ->
    ReturnExpr = lists:last(Body),
    case ReturnExpr of
        {tuple, _, [{atom, _, ok}, {tuple, _, [SupFlagsExpr, ChildrenExpr]}]} ->
            SupFlags = resolve_sup_flags(SupFlagsExpr, Body),
            Children = resolve_children(ChildrenExpr, Body),
            {ok, SupFlags, Children};
        _ ->
            {error, {unexpected_return, ReturnExpr}}
    end.

resolve_sup_flags({map, _, Fields}, _Body) ->
    Strategy = extract_atom_field(Fields, strategy),
    Intensity = extract_integer_field(Fields, intensity),
    Period = extract_integer_field(Fields, period),
    #{
        strategy => Strategy,
        intensity => Intensity,
        period => Period
    };
resolve_sup_flags({var, _, Name}, Body) ->
    case find_match(Name, Body) of
        {ok, Value} -> resolve_sup_flags(Value, Body);
        error -> error({unbound_variable, Name})
    end;
resolve_sup_flags(Other, _Body) ->
    error({dynamic_sup_flags, Other}).

resolve_children({cons, _Line, Head, Tail}, Body) ->
    [parse_child_spec(Head) | resolve_children(Tail, Body)];
resolve_children({nil, _Line}, _Body) ->
    [];
resolve_children({var, _, Name}, Body) ->
    case find_match(Name, Body) of
        {ok, Value} -> resolve_children(Value, Body);
        error -> error({unbound_variable, Name})
    end;
resolve_children(Other, _Body) ->
    error({dynamic_children, Other}).

parse_child_spec({map, _, Fields}) ->
    Id = extract_atom_field(Fields, id),
    Start = extract_start(Fields),
    Restart = extract_restart(Fields),
    Type = extract_type(Fields),
    #{
        id => Id,
        start => Start,
        restart => Restart,
        type => Type
    }.

extract_start(Fields) ->
    case [V || {map_field_assoc, _, {atom, _, start}, V} <- Fields] of
        [{tuple, _, [{atom, _, M}, {atom, _, F}, A]}] ->
            Args = erl_parse:normalise(A),
            {M, F, Args};
        _ ->
            {undefined, undefined, []}
    end.

extract_restart(Fields) ->
    case [V || {map_field_assoc, _, {atom, _, restart}, {atom, _, V}} <- Fields] of
        [R] when R =:= permanent; R =:= transient; R =:= temporary -> R;
        _ -> permanent
    end.

extract_type(Fields) ->
    case [V || {map_field_assoc, _, {atom, _, type}, {atom, _, V}} <- Fields] of
        [supervisor] -> supervisor;
        [worker] -> worker;
        _ -> worker
    end.

extract_atom_field(Fields, Key) ->
    case [V || {map_field_assoc, _, {atom, _, K}, {atom, _, V}} <- Fields, K =:= Key] of
        [Val] -> Val;
        _ -> error({missing_field, Key})
    end.

extract_integer_field(Fields, Key) ->
    case [V || {map_field_assoc, _, {atom, _, K}, {integer, _, V}} <- Fields, K =:= Key] of
        [Val] -> Val;
        _ -> error({missing_field, Key})
    end.

find_match(Name, [{match, _, {var, _, Name}, Value} | _]) ->
    {ok, Value};
find_match(Name, [_ | Rest]) ->
    find_match(Name, Rest);
find_match(_Name, []) ->
    error.

-module(ides_static_beam).

-export([load_beams/1, is_supervisor/1]).

-type beam_info() :: #{
    module := module(),
    attributes := [{atom(), [term()]}],
    exports := [{atom(), arity()}],
    abstract_code => abstr()
}.

-type abstr() :: [term()].

-export_type([beam_info/0]).

-doc "Return true if the module declares `-behaviour(supervisor)`.".
-spec is_supervisor(beam_info()) -> boolean().
is_supervisor(#{attributes := Attrs}) ->
    lists:any(
        fun
            ({behaviour, Behaviours}) when is_list(Behaviours) ->
                lists:member(supervisor, Behaviours);
            (_) ->
                false
        end,
        Attrs
    ).

-doc "Load BEAM files and return metadata indexed by module name.".
-spec load_beams([file:filename()]) -> {ok, #{atom() => beam_info()}}.
load_beams(Paths) ->
    Results = maps:from_list(
        [{Module, Info} || Path <- Paths, {ok, Module, Info} <- [load_beam(Path)]]
    ),
    {ok, Results}.

-spec load_beam(file:filename()) -> {ok, module(), beam_info()} | error.
load_beam(Path) ->
    case beam_lib:chunks(Path, [attributes, exports, abstract_code, debug_info]) of
        {ok, {Module, Chunks}} ->
            Attrs = get_attributes(Chunks),
            Exports = get_exports(Chunks),
            Info = #{
                module => Module,
                attributes => Attrs,
                exports => Exports
            },
            Info2 =
                case extract_abstract_code(Chunks) of
                    {ok, Code} -> Info#{abstract_code => Code};
                    error -> Info
                end,
            {ok, Module, Info2};
        _ ->
            error
    end.

-spec get_attributes([tuple()]) -> [{atom(), [term()]}].
get_attributes(Chunks) ->
    case lists:keyfind(attributes, 1, Chunks) of
        {attributes, Attrs} when is_list(Attrs) -> Attrs;
        _ -> []
    end.

-spec get_exports([tuple()]) -> [{atom(), arity()}].
get_exports(Chunks) ->
    case lists:keyfind(exports, 1, Chunks) of
        {exports, Exports} when is_list(Exports) -> Exports;
        _ -> []
    end.

extract_abstract_code(Chunks) ->
    case proplists:get_value(abstract_code, Chunks) of
        {raw_abstract_v1, Code} ->
            {ok, Code};
        Code when is_list(Code) ->
            {ok, Code};
        _ ->
            case proplists:get_value(debug_info, Chunks) of
                {erl_abstract_code, Forms} when is_list(Forms) ->
                    {ok, Forms};
                {Backend, Metadata} when is_atom(Backend) ->
                    get_raw_abstract_code(Metadata);
                {_Backend, _Backend2, Metadata} ->
                    get_raw_abstract_code(Metadata);
                _ ->
                    error
            end
    end.

get_raw_abstract_code(Metadata) ->
    case proplists:get_value(abstract_code, Metadata) of
        {raw_abstract_v1, Code} -> {ok, Code};
        _ -> error
    end.

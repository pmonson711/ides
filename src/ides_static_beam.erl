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
        fun({behaviour, Behaviours}) ->
            lists:member(supervisor, Behaviours);
           (_) ->
            false
        end,
        Attrs
    ).

-doc "Load BEAM files and return metadata indexed by module name.".
-spec load_beams([file:filename()]) -> {ok, #{module() => beam_info()}}.
load_beams(Paths) ->
    Results = lists:foldl(fun load_beam/2, #{}, Paths),
    {ok, Results}.

load_beam(Path, Acc) ->
    case beam_lib:chunks(Path, [attributes, exports, abstract_code, debug_info]) of
        {ok, {Module, Chunks}} ->
            Attrs = proplists:get_value(attributes, Chunks, []),
            Exports = proplists:get_value(exports, Chunks, []),
            Info = #{
                module => Module,
                attributes => Attrs,
                exports => Exports
            },
            Info2 = case extract_abstract_code(Chunks) of
                {ok, Code} -> Info#{abstract_code => Code};
                error -> Info
            end,
            Acc#{Module => Info2};
        _ ->
            Acc
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
                    case proplists:get_value(abstract_code, Metadata) of
                        {raw_abstract_v1, Code} -> {ok, Code};
                        _ -> error
                    end;
                {_Backend, _Backend2, Metadata} ->
                    case proplists:get_value(abstract_code, Metadata) of
                        {raw_abstract_v1, Code} -> {ok, Code};
                        _ -> error
                    end;
                _ ->
                    error
            end
    end.

-module(ides_tests).

-include_lib("eunit/include/eunit.hrl").

smoke_test() ->
    ?assertEqual(1, 1).

exports_test() ->
    Expected = [{ancestors,1}, {format,2}, {print,2}],
    Exports = [E || {Name,_}=E <- ides:module_info(exports), Name =/= module_info],
    ?assertEqual(lists:sort(Expected),
                 lists:sort(Exports)).

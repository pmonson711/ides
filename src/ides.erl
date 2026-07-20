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
    name     := string(),
    pid      := pid(),
    type     := supervisor,
    strategy := supervisor_strategy(),
    children := [process()]
}.

-type process() :: supervisor_process() | child_process().

-export_type([process/0, supervisor_process/0, child_process/0,
              supervisor_strategy/0, child_restart_type/0]).

-spec ancestors(TargetPid :: pid()) -> {ok, process()} | {error, term()}.
ancestors(_TargetPid) ->
    {error, not_implemented}.

-spec format(TargetPid :: pid(), Tree :: process()) -> iolist().
format(_TargetPid, _Tree) ->
    [].

-spec print(TargetPid :: pid(), Tree :: process()) -> ok.
print(TargetPid, Tree) ->
    io:put_chars(format(TargetPid, Tree)).

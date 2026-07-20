-module(ides).

-doc "Beware the Ides of March — find the supervisors and siblings that could\n"
     "kill your Erlang process.\n"
     "\n"
     "Given any PID, this module shows:\n"
     "- **Ancestors**: the chain of supervisors above the process\n"
     "- **Siblings**: all children of the same supervisor\n"
     "- **Kill graph**: every process that could cause this PID to be killed\n"
     "- **Restart logic**: whether a terminated child will be restarted\n"
     "- **Affected siblings**: which siblings a supervisor would kill/restart\n"
     "  if this PID dies\n"
     "\n"
     "Uses OTP primitives: `erlang:process_info/2` for `$ancestors`,\n"
     "`supervisor:which_children/1`, and `proc_lib:translate_initial_call/1`.".

-export([ancestors/1, format/2, print/2,
         kill_graph/1, should_restart/2, affected_siblings/1]).

-type supervisor_strategy() :: ides_family:supervisor_strategy().
-type child_restart_type() :: ides_family:child_restart_type().
-type child_process() :: ides_family:child_process().
-type supervisor_process() :: ides_family:supervisor_process().
-type process() :: ides_family:process().
-type exit_reason() :: ides_march:exit_reason().

-export_type([process/0, supervisor_process/0, child_process/0,
              supervisor_strategy/0, child_restart_type/0, exit_reason/0]).

%% --- Tree walking ---

-spec ancestors(TargetPid :: pid()) -> {ok, process()} | {error, term()}.
ancestors(TargetPid) ->
    ides_family:ancestors(TargetPid).

%% --- Formatting ---

-spec format(TargetPid :: pid(), Tree :: process()) -> iolist().
format(TargetPid, Tree) ->
    ides_printer:format(TargetPid, Tree).

-spec print(TargetPid :: pid(), Tree :: process()) -> ok.
print(TargetPid, Tree) ->
    ides_printer:print(TargetPid, Tree).

%% --- Kill graph analysis ---

-spec kill_graph(TargetPid :: pid()) -> {ok, [pid()]} | {error, term()}.
kill_graph(TargetPid) ->
    ides_march:kill_graph(TargetPid).

-spec should_restart(Pid :: pid(), Reason :: exit_reason()) -> boolean().
should_restart(Pid, Reason) ->
    ides_march:should_restart(Pid, Reason).

-spec affected_siblings(TargetPid :: pid()) -> {ok, [pid()]} | {error, term()}.
affected_siblings(TargetPid) ->
    ides_march:affected_siblings(TargetPid).

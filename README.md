ides
=====

> [!CAUTION]
> This is currently in beta, and being proven out.

Beware the Ides of March — find the supervisors and siblings that could kill your Erlang process.

Given any PID, **ides** shows:

- **Supervision tree**: the ASCII tree of supervisors and workers
- **Kill graph**: every process that could cause this PID to be killed (supervisors, siblings, links, monitors)
- **Restart logic**: whether a terminated child will be restarted
- **Affected siblings**: which siblings a supervisor would kill/restart if this PID dies
- **Link/monitor info**: processes linked to or monitoring this PID
- **Restart intensity**: configured MaxR/MaxT and current restart count per supervisor

Why ides?
----------

> "Why not just kill the PID and see what breaks?"

Killing a process to observe the blast radius is destructive, reactive, and incomplete:

| Kill-a-PID approach | ides |
|---|---|
| Destructive — actually crashes processes, potentially in production | Read-only — uses OTP introspection primitives, zero side effects |
| Reactive — you learn what happened *after* the damage is done | Predictive — you understand what *will* happen before anything dies |
| Tells you what died (the blast radius) | Tells you what died, *plus* who can kill you (ancestors + killer siblings) |
| Observes effects without explaining the cause | Shows supervisor strategy, restart types, and child position — the *why* behind the outcome |
| No insight into restart behavior — did it come back because it's `permanent`, or was it `temporary`? | Explicitly answers `should_restart/2` based on the child's restart type |
| May leave the system in an unknown state with cascading side effects | Pure analysis — the system stays exactly as it was |
| Hard to test — must account for restart intensity, timing, and supervisor state; often requires custom test scaffolding | Works out of the box on any OTP process, no test setup needed |

In complex supervision trees with nested `one_for_all`, `rest_for_one`, and
escalation boundaries, reasoning about failure domains by hand is error-prone.
ides answers these questions at runtime without a single process crash.

API documentation is generated from source via `rebar3 ex_doc`. See `src/ides.erl`.

Examples
--------

### one_for_one

```
              my_sup (one_for_one, max 1/5s)
              /         \
        my_server     my_statem
       (permanent)   (transient)
```

A child terminating independently does not affect siblings.

```erlang
1> {ok, Tree} = ides:ancestors(MyStatemPid).
2> ides:print(MyStatemPid, Tree).
my_sup (one_for_one, max 1/5s)
    my_server (permanent)
  * my_statem (transient)
ok
```

### one_for_all

```
                 my_sup (one_for_all, max 1/5s)
              /         |          \
        worker_1    worker_2      cache
       (permanent) (permanent) (temporary)
```

Any child terminating abnormally kills and restarts all siblings.

```erlang
1> {ok, Tree} = ides:ancestors(Worker2Pid).
2> ides:print(Worker2Pid, Tree).
my_sup (one_for_all, max 1/5s)
    worker_1 (permanent)
  * worker_2 (permanent)
    cache (temporary)
ok
```

### rest_for_one

```
                my_sup (rest_for_one, max 1/5s)
              /         |          \
         startup     process     cleanup
       (permanent) (permanent) (permanent)
```

A child at position `i` terminating kills and restarts all children at position `i..N`.

```erlang
1> {ok, Tree} = ides:ancestors(ProcessPid).
2> ides:print(ProcessPid, Tree).
my_sup (rest_for_one, max 1/5s)
    startup (permanent)
  * process (permanent)
    cleanup (permanent)
ok
```

### simple_one_for_one

```
           pool_sup (simple_one_for_one, max 1/5s)
              /              \
        handler_1          handler_2
       (permanent)        (permanent)
```

Same as `one_for_one` — children restart independently.

```erlang
1> {ok, Tree} = ides:ancestors(Handler2Pid).
2> ides:print(Handler2Pid, Tree).
pool_sup (simple_one_for_one, max 1/5s)
    handler_1 (permanent)
  * handler_2 (permanent)
ok
```

### Nested escalation

```
             app_sup (one_for_one, max 1/5s)
                |
              sup1 (one_for_all)
              /         \
        worker_1     worker_2
       (permanent)  (permanent)
```

When `sup1` exceeds its restart intensity, it terminates itself — escalating to `app_sup`, which kills all remaining `sup1` children.

```erlang
1> {ok, Tree} = ides:ancestors(Worker2Pid).
2> ides:print(Worker2Pid, Tree).
app_sup (one_for_one, max 1/5s)
    sup1 (one_for_all, permanent, max 1/5s)
        worker_1 (permanent)
      * worker_2 (permanent)
ok
```

### kill_graph

```
              my_sup (one_for_one, max 1/5s)
              /         \
        my_server     my_statem
       (permanent)   (transient)
```

A process's kill graph includes ancestors, killer siblings, linked processes
(if not trapping exits), and monitored processes. Under `one_for_one`, siblings
do not affect each other — but links and monitors still apply.

```erlang
1> {ok, Killers} = ides:kill_graph(MyStatemPid).
2> Killers.
[<0.55.0>]  %% only the parent supervisor
```

Under `one_for_all`, every sibling is a potential killer:

```
               my_sup (one_for_all, max 1/5s)
              /    |    \
        worker_1 worker_2  cache
       (perm)   (perm)    (temp)
```

```erlang
1> {ok, Killers} = ides:kill_graph(Worker2Pid).
%% Killers includes my_sup, worker_1, and cache
```

### should_restart

```erlang
1> ides:should_restart(PermanentChild, normal).  %% true
2> ides:should_restart(TransientChild, normal).  %% false
3> ides:should_restart(TransientChild, abnormal). %% true
4> ides:should_restart(TemporaryChild, abnormal). %% false
```

### affected_siblings

```
              my_sup (rest_for_one, max 1/5s)
            /         |          \
       startup     process     cleanup
      (permanent) (permanent) (permanent)
```

Under `rest_for_one`, a process dying affects itself and all later siblings:

```erlang
1> {ok, Affected} = ides:affected_siblings(ProcessPid).
%% Affected = [process_pid, cleanup_pid]
```

Under `one_for_one`, only the terminated process itself is affected:

```erlang
1> {ok, Affected} = ides:affected_siblings(StartupPid).
%% Affected = [startup_pid]
```

### link_info

```erlang
1> {ok, #{links := Links, traps_exits := Traps}} = ides:link_info(Pid).
%% Links = [<0.100.0>, ...]  — processes linked to Pid
%% Traps = true              — whether Pid traps exits
```

Link killers are included in the kill graph when `traps_exits` is `false` —
a linked process dying abnormally will kill this one.

### monitor_info

```erlang
1> {ok, #{monitors := Monitors, monitored_by := MonitoredBy}} = ides:monitor_info(Pid).
%% Monitors = [<0.200.0>]    — processes Pid is monitoring
%% MonitoredBy = [<0.50.0>]  — processes monitoring Pid
```

Monitor killers are included in the kill graph — an unhandled DOWN message
can crash the monitoring process.

### kill_graph_detail

Returns the kill graph with each entry tagged by its mechanism:

```erlang
1> {ok, Sources} = ides:kill_graph_detail(Pid).
%% [{ancestor, <0.55.0>},
%%  {sibling,  <0.60.0>},
%%  {link,     <0.100.0>},
%%  {monitor,  <0.200.0>}]
```

### format_detail / print_detail

Like `format/2` but appends the annotated kill graph:

```erlang
1> {ok, Tree} = ides:ancestors(Pid).
2> {ok, Sources} = ides:kill_graph_detail(Pid).
3> ides:print_detail(Pid, Tree, Sources).
my_sup (one_for_one, max 1/5s)
    my_server (permanent)
  * my_statem (transient)

Kill Graph:
  ancestors: <0.55.0>
  siblings : (none)
  links    : <0.100.0>
  monitors : <0.200.0>
ok
```

### intensity_info

Returns the configured restart intensity policy and current count
(if extractable from OTP state):

```erlang
1> {ok, Info} = ides:intensity_info(SupPid).
%% #{max_restarts => 1, max_period => 5, current_count => 2, remaining => 0}
```

Without runtime state access, falls back to policy-only reporting.

How
---

Uses OTP primitives:

- `erlang:process_info(Pid, dictionary)` → `$ancestors` — finds the supervisor chain
- `supervisor:which_children(ParentPid)` → lists all siblings
- `sys:get_state(SupPid)` → extracts strategy, intensity, and restart counts
- `proc_lib:translate_initial_call(Pid)` → human-readable process labels
- `erlang:process_info(Pid, [links, trap_exit])` → link relationships
- `erlang:process_info(Pid, [monitors, monitored_by])` → monitor relationships

Caveats
-------

- `$ancestors` only exists for processes started via `proc_lib` (OTP behaviours)
- `$ancestors` is set at spawn time — stale if a supervisor restarts
- Tree recursion uses `supervisor:which_children/1`, recursing on children with `type =:= supervisor`

Build
-----

    $ rebar3 compile

ides
=====

> [!CAUTION]
> This is currently in beta, and being proven out.

Beware the Ides of March — find the supervisors and siblings that could kill your Erlang process.

Given any PID, **ides** shows:

- **Ancestors**: the chain of supervisors above the process
- **Siblings**: all children of the same supervisor
- **Kill graph**: every process that could cause this PID to be killed
- **Restart logic**: whether a terminated child will be restarted
- **Affected siblings**: which siblings a supervisor would kill/restart if this PID dies

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
              my_sup (one_for_one)
              /         \
        my_server     my_statem
       (permanent)   (transient)
```

A child terminating independently does not affect siblings.

```erlang
1> {ok, Tree} = ides:ancestors(MyStatemPid).
2> ides:print(MyStatemPid, Tree).
my_sup (one_for_one)
    my_server (permanent)
  * my_statem (transient)
ok
```

### one_for_all

```
                 my_sup (one_for_all)
              /         |          \
        worker_1    worker_2      cache
       (permanent) (permanent) (temporary)
```

Any child terminating abnormally kills and restarts all siblings.

```erlang
1> {ok, Tree} = ides:ancestors(Worker2Pid).
2> ides:print(Worker2Pid, Tree).
my_sup (one_for_all)
    worker_1 (permanent)
  * worker_2 (permanent)
    cache (temporary)
ok
```

### rest_for_one

```
                my_sup (rest_for_one)
              /         |          \
         startup     process     cleanup
       (permanent) (permanent) (permanent)
```

A child at position `i` terminating kills and restarts all children at position `i..N`.

```erlang
1> {ok, Tree} = ides:ancestors(ProcessPid).
2> ides:print(ProcessPid, Tree).
my_sup (rest_for_one)
    startup (permanent)
  * process (permanent)
    cleanup (permanent)
ok
```

### simple_one_for_one

```
           pool_sup (simple_one_for_one)
              /              \
        handler_1          handler_2
       (permanent)        (permanent)
```

Same as `one_for_one` — children restart independently.

```erlang
1> {ok, Tree} = ides:ancestors(Handler2Pid).
2> ides:print(Handler2Pid, Tree).
pool_sup (simple_one_for_one)
    handler_1 (permanent)
  * handler_2 (permanent)
ok
```

### Nested escalation

```
             app_sup (one_for_one)
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
app_sup (one_for_one)
    sup1 (one_for_all, permanent)
        worker_1 (permanent)
      * worker_2 (permanent)
ok
```

### kill_graph

```
              my_sup (one_for_one)
              /         \
        my_server     my_statem
       (permanent)   (transient)
```

A process's kill graph includes ancestors plus any siblings that could
trigger a cascade restart. Under `one_for_one`, siblings do not affect each other.

```erlang
1> {ok, Killers} = ides:kill_graph(MyStatemPid).
2> Killers.
[<0.55.0>]  %% only the parent supervisor
```

Under `one_for_all`, every sibling is a potential killer:

```
               my_sup (one_for_all)
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
              my_sup (rest_for_one)
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

How
---

Uses OTP primitives:

- `erlang:process_info(Pid, dictionary)` → `$ancestors` — finds the supervisor chain
- `supervisor:which_children(ParentPid)` → lists all siblings
- `proc_lib:translate_initial_call(Pid)` → human-readable process labels

Caveats
-------

- `$ancestors` only exists for processes started via `proc_lib` (OTP behaviours)
- `$ancestors` is set at spawn time — stale if a supervisor restarts
- Tree recursion uses `supervisor:which_children/1`, recursing on children with `type =:= supervisor`

Build
-----

    $ rebar3 compile

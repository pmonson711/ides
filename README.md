ides
=====

Beware the Ides of March — find the supervisors and siblings that could kill your Erlang process.

Given any PID, **ides** shows:

- **Ancestors**: the chain of supervisors above the process
- **Siblings**: all children of the same supervisor that could cause this process to be killed

API
---

```erlang
-export([ancestors/1, print/2, format/2]).
```

### ancestors(Pid)

Walk the supervision tree from the topmost ancestor down to `Pid`.
Returns the tree including the ancestor chain and all siblings at each level.

```erlang
-spec ancestors(TargetPid :: pid()) -> {ok, ides:process()} | {error, term()}.
```

### print(TargetPid, Tree)

Render the tree as indented text to stdout. The target process is marked with `*`.

```erlang
-spec print(TargetPid :: pid(), Tree :: ides:process()) -> ok.
```

### format(TargetPid, Tree)

Like `print/2` but returns an `iolist` instead of writing to stdout.

```erlang
-spec format(TargetPid :: pid(), Tree :: ides:process()) -> iolist().
```

### Data types

```erlang
-type process() :: supervisor_process() | child_process().

-type supervisor_process() :: #{
    name     := string(),
    pid      := pid(),
    type     := supervisor,
    strategy := supervisor_strategy(),
    children := [process()]
}.

-type child_process() :: #{
    name         := string(),
    pid          := pid(),
    type         := worker,
    restart_type := child_restart_type()
}.

-type supervisor_strategy() :: one_for_one
                             | one_for_all
                             | rest_for_one
                             | simple_one_for_one.

-type child_restart_type() :: permanent
                             | transient
                             | temporary.
```

### Rendering rules

| Node               | Format                            |
|--------------------|-----------------------------------|
| Root supervisor    | `name (strategy)`                 |
| Supervisor child   | `name (strategy, restart_type)`   |
| Worker child       | `name (restart_type)`             |
| Target process     | prefixed with `*`                 |

Indentation is 4 spaces per tree level.

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

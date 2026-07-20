ides
=====

Beware the Ides of March — find the supervisors and siblings that could kill your Erlang process.

Given any PID, **ides** shows:
- **Ancestors**: the chain of supervisors above the process
- **Siblings**: all children of the same supervisor that could cause this process to be killed

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

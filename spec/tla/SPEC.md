# TLA+ Supervisor Specs

TLA+ specifications modeling Erlang/OTP supervisor behavior: restart
strategies, link propagation, monitor/DOWN messages, restart-intensity
escalation, and cascading failures.  Used as a formal design reference
for the **ides** application.

## File Organization

| File | Role |
|------|------|
| `SupervisorTree.tla` | Static configuration: constants, type enums, tree helpers (`ParentOf`, `AncestorsOf`), `KillGraph`, `AffectedChildren`, `ShouldRestart` |
| `SupervisorModel.tla` | Dynamic state machine: all actions (`NormalTermination`, `AbnormalTermination`, `LinkKill`, `MonitorCrash`, `SupervisorReacts`), all invariants |
| `MC*.tla` | Model-checking instances: each configures a specific tree topology and checks a subset of invariants |
| `MC*.cfg` | TLC configuration files declaring which invariants and spec to check |

## Glossary

**Restart strategy** — Per-supervisor policy for handling child termination:
- `one_for_one` — only the terminated child is affected
- `one_for_all` — all children are terminated and restarted
- `rest_for_one` — the terminated child and all children after it (by order) are affected
- `simple_one_for_one` — like one_for_one, but children share the same spec (dynamic)

**Restart type** — Per-child policy for whether restarts are attempted:
- `permanent` — always restart regardless of exit reason
- `transient` — restart only on abnormal exit
- `temporary` — never restart

**MaxR** — Maximum number of restarts a supervisor may perform within its time window
**MaxT** — Duration (in clock ticks) of the sliding restart window. Restarts older than `clock - MaxT` are forgotten.
**MaxClock** — Upper bound on the clock variable; keeps the state space finite for model-checking.

**Restart window** — Per-supervisor sequence of timestamps recording recent restarts. Used to compute restart intensity: if `Count(window entries > clock - MaxT) >= MaxR`, the supervisor exceeds intensity and terminates itself.

**Intensity escalation** — When a supervisor exceeds its `MaxR` in `MaxT`, it terminates itself abnormally. Its parent supervisor then reacts, potentially escalating further up the tree.

**KillGraph(P)** — The set of all processes whose termination could cause P to die. Union of:
- Ancestors (any could escalate and kill everything below)
- Strategy-dependent siblings (OneForAll kills all, RestForOne kills later indices)
- Linked processes (exit signals kill P if P doesn't trap exits)
- Monitored processes (DOWN messages kill P if P doesn't handle DOWN)

**Affected children** — The set of children a supervisor acts on when reacting to termination. Differs by strategy: `one_for_one`/`simple_one_for_one` affect only the terminated child; `one_for_all` affects all children; `rest_for_one` affects the terminated child and all children after it.

**Link propagation** — When a process dies abnormally, all processes linked to it that don't trap exits also die. Modeled by the `LinkKill` action and the `LinkKillersOf` helper.

**Monitor/DOWN** — When a monitored process dies, any process monitoring it that doesn't handle DOWN messages crashes. Modeled by the `MonitorCrash` action and the `MonitorKillersOf` helper.

## Invariants

| Invariant | What It Catches |
|-----------|----------------|
| `TypeOK` | State variables stay within their expected types and ranges |
| `TreeWellFormed` | Tree structure is valid (no orphaned children, no cycles, root is root) |
| `RestartTypeCorrect` | Permanent children are never left terminated with a running supervisor; transient children only restart on abnormal exit; temporary children never restart |
| `StrategySemantics` | Supervisor's strategy is followed correctly: after `SupervisorReacts`, all affected children are either running or shouldn't be restarted |
| `IntensityEscalation` | No running supervisor has exceeded its MaxR/MaxT restart intensity |
| `KillGraphCorrect` | Any process killed by a supervisor reaction has some process in its kill graph that terminated first |
| `LinkPropagationCorrect` | After a process dies abnormally, all linked non-trapping processes are terminated |
| `MonitorCrashInKillGraph` | Processes that crash from unhandled DOWN have the dead monitored process in their kill graph |
| `KillGraphDeep` | Every worker's full ancestor chain is in its kill graph |
| `CascadeCorrect` | After a supervisor reacts, any terminated supervisor-child must either have its parent terminated (escalated) or be restarted |

## Model-Checking Scenarios

| Config File | What It Exercises |
|-------------|-------------------|
| `MCOneForOne.tla` | OneForOne strategy, restart type correctness (permanent vs transient), shallow intensity limits |
| `MCOneForAll.tla` | OneForAll strategy (all children restart together), temporary children |
| `MCRestForOne.tla` | RestForOne strategy (ordered cascade), restart intensity |
| `MCSimpleOneForOne.tla` | SimpleOneForOne strategy (identical to OneForOne in static tree) |
| `MCNestedEscalation.tla` | Nested supervisors, OneForAll under OneForOne, intensity escalation |
| `MCNestedDeep3.tla` | 3-level nested tree with mixed strategies, deep cascade verification |
| `MCNestedDeep4.tla` | 4-level deep chain, stress-testing full depth escalation through all strategies |
| `MCLinkKill.tla` | Link propagation: partially linked workers with mixed trap-exit settings |
| `MCMonitorCrash.tla` | Monitor/DOWN cascade: chain of monitored processes with mixed handle-DOWN settings |

## How to Run TLC

Install the TLA+ Toolbox and run from `spec/tla/`:

```sh
# Shallow trees (fast)
mise exec -- java -cp tla2tools.jar tlc2.TLC MCOneForOne.tla

# Line counts show state-space size. Shallow configs finish
# quickly (<100 states); deep configs may need -workers N.

# Nested/deep trees
mise exec -- java -cp tla2tools.jar tlc2.TLC -workers 4 MCNestedDeep4.tla
```

## Modeling Notes

**What's modeled:**
- All four supervisor restart strategies
- All three child restart types
- Restart intensity with escalation (supervisor self-terminates on overflow)
- Normal and abnormal process termination
- Link propagation (exit signal kills linked processes that don't trap exits)
- Monitor/DOWN propagation (dead process kills monitors that don't handle DOWN)
- Cascading failures through nested supervisors

**What's abstracted:**
- No message passing (only structure-level propagation)
- No code loading or process spawning
- Static topology — no runtime add/delete of children
- Bounded clock for finite model-checking (MaxClock)
- Discrete clock ticks with no real-time semantics

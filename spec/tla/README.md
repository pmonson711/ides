# TLA+ Supervisor Model

A TLA+ specification modeling Erlang OTP supervisor behavior, used as a
design reference for the **ides** application (prints an ASCII supervision
tree for a given PID).

## Files

### Core Spec

| File | Purpose |
|------|---------|
| `SupervisorTree.tla` | Constants, type definitions, derived operators (`KillGraph`, `ParentOf`, `ShouldRestart`, etc.) |
| `SupervisorModel.tla` | State variables, transitions (`NormalTermination`, `AbnormalTermination`, `SupervisorReacts`), `Spec`, and all invariants |

### Model-Checking Configs

Each pair is a concrete instance for a specific strategy. Run with:
`tla spec/tla/MCOneForOne.cfg` (or use the `tla` wrapper).

| Files | Topology | What It Tests |
|-------|----------|---------------|
| `MCOneForOne.tla/.cfg` | 1 supervisor → 2 workers (perm, trans) | Independent restarts; transient+normal = no restart |
| `MCOneForAll.tla/.cfg` | 1 supervisor → 3 workers (perm, perm, temp) | All siblings killed on any death; temporary stays dead |
| `MCRestForOne.tla/.cfg` | 1 supervisor → 3 workers (all perm) | Cascade kills child at position i and all after |
| `MCSimpleOneForOne.tla/.cfg` | 1 supervisor → 2 workers (all perm) | Independent restarts like OneForOne |
| `MCNestedEscalation.tla/.cfg` | Root → sup1 (one_for_all) → 2 workers | Intensity escalation propagates up the tree |

## Invariants

All configs check the same six invariants:

| Invariant | What It Ensures |
|-----------|-----------------|
| `TypeOK` | State variables stay within their type domains |
| `RestartTypeCorrect` | Permanent children always restarted; temporary never |
| `StrategySemantics` | Each strategy behaves correctly (OneForAll kills all, RestForOne cascades, etc.) |
| `IntensityEscalation` | Supervisor terminates itself if restart count exceeds `MaxR` |
| `KillGraphCorrect` | Every child killed by a supervisor has a killer in its `KillGraph` |

## Kill Graph

`KillGraph(P)` computes all processes whose termination could kill P:

- **Parent**: always in the kill graph — a dead supervisor kills all children
- **Siblings via strategy**: `OneForAll` → all siblings; `RestForOne` → siblings at lower positions; `OneForOne`/`SimpleOneForOne` → none
- **Ancestors via escalation**: any supervisor above P whose restart intensity overflows kills P transitively

This definition directly guides the ides Erlang implementation.

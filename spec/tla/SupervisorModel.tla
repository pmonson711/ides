---- MODULE SupervisorModel ----
EXTENDS Naturals, Sequences, SupervisorTree

(*
  SupervisorModel — Dynamic state machine for the Erlang supervisor model.

  Models Erlang/OTP supervisor behavior as a TLA+ next-state relation
  with five actions and a set of invariants:

  Actions (corresponding to real Erlang mechanisms):
    NormalTermination(p)   — Process exits with reason normal
    AbnormalTermination(p) — Process crashes with abnormal exit;
                              link victims killed in the same step
    LinkKill(p)            — Link propagation: partner of a dead
                              process dies if it doesn't trap exits
    MonitorCrash(p)        — Monitor/DOWN: process dies if it
                              doesn't handle DOWN from a monitored process
    SupervisorReacts(sup)  — Supervisor restarts terminated children
                              per strategy, restart type, and
                              intensity limits; terminates itself
                              and children on intensity overflow

  State variables:
    clock          — Monotonic tick, bounded at MaxClock
    proc_state     — Per-process: Running/Terminated, exit reason, type
    restart_window — Per-supervisor: sequence of restart timestamps
    history        — Last action taken (for action-level invariants)
    monitor_down   — Per-process: set of monitored processes known down

  Invariants (see inline comments for what each catches):
    TypeOK, TreeWellFormed, RestartTypeCorrect, StrategySemantics,
    IntensityEscalation, KillGraphCorrect, LinkPropagationCorrect,
    MonitorCrashInKillGraph, KillGraphDeep, CascadeCorrect
*)

VARIABLES clock, proc_state, restart_window, history, monitor_down

vars == <<clock, proc_state, restart_window, history, monitor_down>>

\* Per-process state record type
ProcState == [ state      : {Running, Terminated},
               exit       : ExitReasons,
               type       : ProcTypes,
               init_phase : InitPhases ]

\* History record for action-level invariant checks
HistoryRec == [ action : {"Init", "NormalTermination", "AbnormalTermination", "LinkKill", "MonitorCrash", "SupervisorReacts", "Tick", "StartChild", "InitSuccess", "InitTimeout"},
                pid    : Processes ]

TypeOK ==
  /\ clock \in 0..MaxClock
  /\ proc_state \in [Processes -> ProcState]
  /\ restart_window \in [Processes -> Seq(0..MaxClock)]
  /\ history \in HistoryRec
  /\ monitor_down \in [Processes -> SUBSET Processes]

Init ==
  /\ clock = 0
  /\ proc_state = [p \in Processes |->
       [state |-> Running,
        exit  |-> Normal,
        type  |-> IF IsSupervisor(p) THEN SupervisorType ELSE WorkerType,
        init_phase |-> Running]]
  /\ restart_window = [p \in Processes |-> <<>>]
  /\ history = [action |-> "Init", pid |-> Root]
  /\ monitor_down = [p \in Processes |-> {}]

StartChild(sup, child) ==
  /\ IsSupervisor(sup)
  /\ child \in SeqToSet(ChildrenOf[sup])
  /\ proc_state[child].init_phase = Idle
  /\ proc_state' = [proc_state EXCEPT ![child].init_phase = Initing]
  /\ history' = [action |-> "StartChild", pid |-> child]
  /\ clock' = clock
  /\ UNCHANGED <<restart_window, monitor_down>>

InitSuccess(p) ==
  /\ proc_state[p].init_phase = Initing
  /\ proc_state' = [proc_state EXCEPT ![p].init_phase = Running]
  /\ history' = [action |-> "InitSuccess", pid |-> p]
  /\ clock' = clock
  /\ UNCHANGED <<restart_window, monitor_down>>

InitTimeout(p) ==
  /\ proc_state[p].init_phase = Initing
  /\ proc_state' = [proc_state EXCEPT ![p] = [@ EXCEPT !.state = Terminated, !.exit = Abnormal, !.init_phase = InitTimedOut]]
  /\ history' = [action |-> "InitTimeout", pid |-> p]
  /\ clock' = clock
  /\ UNCHANGED <<restart_window, monitor_down>>

Tick ==
  /\ clock < MaxClock
  /\ clock' = clock + 1
  /\ history' = [action |-> "Tick", pid |-> Root]
  /\ UNCHANGED <<proc_state, restart_window, monitor_down>>
NormalTermination(p) ==
  /\ proc_state[p].state = Running
  /\ proc_state' = [proc_state EXCEPT ![p] = [@ EXCEPT !.state = Terminated, !.exit = Normal]]
  /\ history' = [action |-> "NormalTermination", pid |-> p]
  /\ clock' = clock
  /\ UNCHANGED <<restart_window, monitor_down>>

AbnormalTermination(p) ==
  /\ proc_state[p].state = Running
  /\ LET link_victims == {q \in Links[p] : q /= p /\ ~TrapsExits[q]
                                /\ proc_state[q].state = Running}
     IN /\ proc_state' = [q \in Processes |->
              CASE q = p ->
                [state |-> Terminated, exit |-> Abnormal, type |-> proc_state[q].type, init_phase |-> proc_state[q].init_phase]
              [] q \in link_victims ->
                [state |-> Terminated, exit |-> Abnormal, type |-> proc_state[q].type, init_phase |-> proc_state[q].init_phase]
             [] OTHER -> proc_state[q]]
  /\ history' = [action |-> "AbnormalTermination", pid |-> p]
  /\ clock' = clock
  /\ UNCHANGED <<restart_window, monitor_down>>

\* Link propagation: when p terminates abnormally, kill all linked
\* processes that don't trap exits.
LinkKill(p) ==
  /\ proc_state[p].state = Terminated
  /\ proc_state[p].exit = Abnormal
  /\ LET victims == {q \in Links[p] : q /= p /\ ~TrapsExits[q]
                           /\ proc_state[q].state = Running}
     IN /\ victims # {}
         /\ proc_state' = [q \in Processes |->
              CASE q \in victims ->
                [state |-> Terminated, exit |-> Abnormal, type |-> proc_state[q].type, init_phase |-> proc_state[q].init_phase]
              [] OTHER -> proc_state[q]]
         /\ history' = [action |-> "LinkKill", pid |-> p]
        /\ clock' = clock
        /\ UNCHANGED <<restart_window, monitor_down>>

\* Monitor crash: when a monitored process terminates, monitoring
\* processes that don't handle DOWN messages crash.
MonitorCrash(p) ==
  /\ proc_state[p].state = Terminated
  /\ LET victims == {q \in Processes : p \in Monitors[q]
                           /\ ~HandlesDown[q]
                           /\ proc_state[q].state = Running}
     IN /\ victims # {}
         /\ proc_state' = [q \in Processes |->
              CASE q \in victims ->
                [state |-> Terminated, exit |-> Abnormal, type |-> proc_state[q].type, init_phase |-> proc_state[q].init_phase]
              [] OTHER -> proc_state[q]]
         /\ history' = [action |-> "MonitorCrash", pid |-> p]
        /\ clock' = clock
        /\ UNCHANGED <<restart_window, monitor_down>>

SupervisorReacts(sup) ==
  (* --- Step 1: Affected children — which children this supervisor must act on,
      determined by strategy (see AffectedChildren in SupervisorTree.tla) --- *)
  LET children_set  == SeqToSet(ChildrenOf[sup])
      terminated    == {c \in children_set : proc_state[c].state = Terminated}
  IN /\ IsSupervisor(sup)
     /\ terminated # {}
     (* --- Step 2: Restart eligibility and intensity check.
         ShouldRestart filters affected children by restart type.
         The restart_window check decides: normal restart vs escalation crash. --- *)
     /\ LET affected    == AffectedChildren(sup, terminated)
            to_restart  == {c \in affected : ShouldRestart(c, proc_state)}
            \* Children the supervisor kills (were running, now terminated by supervisor)
            newly_killed == {c \in affected \ terminated : proc_state[c].state = Running}
         IN /\ clock' = clock
            /\ monitor_down' = monitor_down
            /\ history' = [action |-> "SupervisorReacts", pid |-> sup]
            (* --- Step 3: State update — either restart+kill children normally,
                or if intensity exceeded, terminate the supervisor and all children
                (escalation to parent). --- *)
           /\ IF Len(restart_window[sup]) + Cardinality(to_restart) > MaxR[sup]
              THEN \* Restart intensity exceeded: supervisor terminates all children and itself
                   /\ restart_window' = restart_window
                   /\ proc_state' = [p \in Processes |->
                         CASE p = sup \/ p \in children_set ->
                           [state |-> Terminated, exit |-> Abnormal, type |-> proc_state[p].type, init_phase |-> proc_state[p].init_phase]
                        [] OTHER -> proc_state[p]]
              ELSE \* Restart eligible children, kill newly affected, leave others
                   /\ restart_window' = [restart_window EXCEPT ![sup] =
                        LET count == Cardinality(to_restart)
                            entries == [t \in 1..count |-> clock]
                        IN restart_window[sup] \o entries]
                   /\ proc_state' = [p \in Processes |->
                         CASE p \in to_restart ->
                           [state |-> Running, exit |-> Normal, type |-> proc_state[p].type, init_phase |-> Running]
                         [] p \in newly_killed ->
                           [state |-> Terminated, exit |-> Abnormal, type |-> proc_state[p].type, init_phase |-> proc_state[p].init_phase]
                        [] OTHER -> proc_state[p]]

Next ==
  \/ \E sup \in {s \in Processes : IsSupervisor(s)} : \E child \in SeqToSet(ChildrenOf[sup]) : StartChild(sup, child)
  \/ \E p \in Processes : InitSuccess(p)
  \/ \E p \in Processes : InitTimeout(p)
  \/ \E p \in Processes : NormalTermination(p)
  \/ \E p \in Processes : AbnormalTermination(p)
  \/ \E p \in Processes : MonitorCrash(p)
  \/ \E sup \in {s \in Processes : IsSupervisor(s)} : SupervisorReacts(sup)

Spec == Init /\ [][Next]_vars

\* --- Invariants ---

\* Every non-Root process has exactly one parent, Root has no parent,
\* and there are no cycles.
TreeWellFormed ==
  /\ LET ParentsOf[q \in Processes] ==
       IF q = Root THEN {}
       ELSE {sup \in Processes : q \in SeqToSet(ChildrenOf[sup])}
     IN \A p \in Processes \ {Root} : Cardinality(ParentsOf[p]) = 1
  /\ \A p \in Processes : Root \notin SeqToSet(ChildrenOf[p])
  /\ \A p \in Processes : p = Root \/ Root \in AncestorsOf(p)

\* INVARIANT: Permanent children must always be Running while their
\* supervisor is Running.  Transient children only restart on Abnormal
\* exit.  Temporary children never restart.
\* Catches: a supervisor failing to restart a child per its restart type.
RestartTypeCorrect ==
  (history.action = "SupervisorReacts") =>
    LET sup == history.pid
        children_set == SeqToSet(ChildrenOf[sup])
    IN
    /\ \A c \in {c \in children_set : RestartType[c] = Permanent} :
         proc_state[c].state = Running \/ proc_state[sup].state = Terminated
    /\ \A c \in {c \in children_set : RestartType[c] = Temporary} :
         proc_state[c].state = Terminated \/ proc_state[sup].state = Terminated

\* INVARIANT: After a supervisor reacts, its children respect the
\* supervisor's restart strategy:
\*   OneForAll — all children are Running or don't need restart
\*   RestForOne — if a child at index i is Terminated and shouldn't
\*     restart, all children before it are also Terminated (cascade)
\*   OneForOne/SimpleOneForOne — terminated children don't need restart
\* Catches: incorrect cascade logic or missed restarts per strategy.
StrategySemantics ==
  (history.action = "SupervisorReacts") =>
    LET sup == history.pid
        children_set == SeqToSet(ChildrenOf[sup])
    IN CASE Strategy[sup] = OneForAll ->
      proc_state[sup].state = Terminated \/
      (\A c \in children_set :
         proc_state[c].state = Running \/
         ~ShouldRestart(c, proc_state))
    [] Strategy[sup] = RestForOne ->
      proc_state[sup].state = Terminated \/
      (\A i \in 1..Len(ChildrenOf[sup]) :
         LET c == ChildrenOf[sup][i]
         IN (proc_state[c].state = Terminated /\ ~ShouldRestart(c, proc_state)) =>
            (\A j \in 1..(i-1) :
               LET d == ChildrenOf[sup][j]
               IN proc_state[d].state = Terminated \/ ~ShouldRestart(d, proc_state)))
    [] OTHER ->
      \* OneForOne, SimpleOneForOne: terminated children must not need restart
      proc_state[sup].state = Terminated \/
      (\A c \in children_set :
         (proc_state[c].state = Terminated) =>
         ~ShouldRestart(c, proc_state))

\* INVARIANT: No Running supervisor has exceeded its restart intensity
\* (MaxR restarts within MaxT ticks).  If a supervisor would exceed,
\* it must be Terminated (escalated to its parent).
\* Catches: a supervisor exceeding intensity but remaining alive.
IntensityEscalation ==
  \A sup \in {s \in Processes : IsSupervisor(s)} :
    (proc_state[sup].state = Running) =>
    (Len(restart_window[sup]) <= MaxR[sup])

\* INVARIANT: Any child killed by a supervisor reaction (Abnormal exit)
\* must have some process in its KillGraph that terminated first.
\* Catches: a supervisor killing a child that wasn't vulnerable
\* (no kill-graph trigger fired).
KillGraphCorrect ==
  (history.action = "SupervisorReacts") =>
    LET sup     == history.pid
        children_set == SeqToSet(ChildrenOf[sup])
        \* Children killed by supervisor: Terminated with Abnormal exit
        killed   == {c \in children_set :
                       proc_state[c].state = Terminated /\
                       proc_state[c].exit = Abnormal}
    IN \A p \in killed :
      \E killer \in KillGraph(p) :
        proc_state[killer].state = Terminated

\* INVARIANT: After a process dies abnormally, all linked non-trapping
\* processes must be Terminated.
\* Catches: missed link propagation — a linked process surviving a
\* partner's abnormal death without trapping exits.
LinkPropagationCorrect ==
  (history.action = "AbnormalTermination") =>
    LET p == history.pid
    IN \A q \in Processes :
      (q \in Links[p] /\ q /= p /\ ~TrapsExits[q]) =>
      proc_state[q].state = Terminated

\* INVARIANT: Processes that crash from unhandled DOWN must have the
\* dead monitored process in their kill graph.
\* Catches: monitor/DOWN propagation killing a process that shouldn't
\* have been vulnerable (e.g., it handled DOWN).
MonitorCrashInKillGraph ==
  (history.action = "MonitorCrash") =>
    LET killed_pid == history.pid
        victims == {q \in Processes : killed_pid \in Monitors[q]
                           /\ ~HandlesDown[q]
                           /\ proc_state[q].state = Terminated}
    IN \A v \in victims : killed_pid \in KillGraph(v)

\* INVARIANT: Every worker's full ancestor chain is in its KillGraph.
\* Catches: a worker missing ancestors from its kill graph, which
\* would mean escalation from above can't reach it in the analysis.
KillGraphDeep ==
  \A p \in {q \in Processes : IsWorker(q)} :
    AncestorsOf(p) \subseteq KillGraph(p)

\* INVARIANT: After a supervisor reacts, any terminated supervisor-child
\* must either have its parent terminated (escalation propagated up) or
\* have been restarted back to Running.
\* Catches: a terminated peer supervisor stuck dead — the parent should
\* have either escalated or restarted it.
CascadeCorrect ==
  (history.action = "SupervisorReacts") =>
    LET sup == history.pid
    IN \A c \in SeqToSet(ChildrenOf[sup]) :
      (IsSupervisor(c) /\ proc_state[c].state = Terminated) =>
      (proc_state[sup].state = Terminated \/ proc_state[c].state = Running)

\* After any InitTimeout, if the parent supervisor's restart budget
\* is exceeded, the supervisor must be terminated.
StartupIntensityCorrect ==
  (history.action = "InitTimeout") =>
    LET p == history.pid
        sup == ParentOf(p)
        count == RestartCount(sup, restart_window, clock)
        max_r == MaxR[sup]
    IN (count > max_r) =>
       proc_state[sup].state = Terminated
====

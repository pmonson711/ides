---- MODULE SupervisorModel ----
EXTENDS Naturals, Sequences, SupervisorTree

VARIABLES clock, proc_state, restart_window, history

vars == <<clock, proc_state, restart_window, history>>

\* Per-process state record type
ProcState == [ state : {Running, Terminated},
               exit  : ExitReasons,
               type  : ProcTypes ]

\* History record for action-level invariant checks
HistoryRec == [ action : {"Init", "NormalTermination", "AbnormalTermination", "SupervisorReacts", "Tick"},
                pid    : Processes ]

TypeOK ==
  /\ clock \in 0..MaxClock
  /\ proc_state \in [Processes -> ProcState]
  /\ restart_window \in [Processes -> Seq(0..MaxClock)]
  /\ history \in HistoryRec

Init ==
  /\ clock = 0
  /\ proc_state = [p \in Processes |->
       [state |-> Running,
        exit  |-> Normal,
        type  |-> IF IsSupervisor(p) THEN SupervisorType ELSE WorkerType]]
  /\ restart_window = [p \in Processes |-> <<>>]
  /\ history = [action |-> "Init", pid |-> Root]

Tick ==
  /\ clock < MaxClock
  /\ clock' = clock + 1
  /\ history' = [action |-> "Tick", pid |-> Root]
  /\ UNCHANGED <<proc_state, restart_window>>

NormalTermination(p) ==
  /\ proc_state[p].state = Running
  /\ proc_state' = [proc_state EXCEPT ![p] = [@ EXCEPT !.state = Terminated, !.exit = Normal]]
  /\ history' = [action |-> "NormalTermination", pid |-> p]
  /\ clock' = clock
  /\ UNCHANGED restart_window

AbnormalTermination(p) ==
  /\ proc_state[p].state = Running
  /\ proc_state' = [proc_state EXCEPT ![p] = [@ EXCEPT !.state = Terminated, !.exit = Abnormal]]
  /\ history' = [action |-> "AbnormalTermination", pid |-> p]
  /\ clock' = clock
  /\ UNCHANGED restart_window

SupervisorReacts(sup) ==
  LET children_set  == SeqToSet(ChildrenOf[sup])
      terminated    == {c \in children_set : proc_state[c].state = Terminated}
  IN /\ IsSupervisor(sup)
     /\ terminated # {}
     /\ LET affected    == AffectedChildren(sup, terminated)
            to_restart  == {c \in affected : ShouldRestart(c, proc_state)}
            \* Children the supervisor kills (were running, now terminated by supervisor)
            newly_killed == {c \in affected \ terminated : proc_state[c].state = Running}
        IN /\ clock' = clock
           /\ history' = [action |-> "SupervisorReacts", pid |-> sup]
           /\ IF Len(restart_window[sup]) + Cardinality(to_restart) > MaxR[sup]
              THEN \* Restart intensity exceeded: supervisor terminates all children and itself
                   /\ restart_window' = restart_window
                   /\ proc_state' = [p \in Processes |->
                        CASE p = sup \/ p \in children_set ->
                          [state |-> Terminated, exit |-> Abnormal, type |-> proc_state[p].type]
                        [] OTHER -> proc_state[p]]
              ELSE \* Restart eligible children, kill newly affected, leave others
                   /\ restart_window' = [restart_window EXCEPT ![sup] =
                        LET count == Cardinality(to_restart)
                            entries == [t \in 1..count |-> clock]
                        IN restart_window[sup] \o entries]
                   /\ proc_state' = [p \in Processes |->
                        CASE p \in to_restart ->
                          [state |-> Running, exit |-> Normal, type |-> proc_state[p].type]
                        [] p \in newly_killed ->
                          [state |-> Terminated, exit |-> Abnormal, type |-> proc_state[p].type]
                        [] OTHER -> proc_state[p]]

Next ==
  \/ \E p \in Processes : NormalTermination(p)
  \/ \E p \in Processes : AbnormalTermination(p)
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

RestartTypeCorrect ==
  (history.action = "SupervisorReacts") =>
    LET sup == history.pid
        children_set == SeqToSet(ChildrenOf[sup])
    IN
    /\ \A c \in {c \in children_set : RestartType[c] = Permanent} :
         proc_state[c].state = Running \/ proc_state[sup].state = Terminated
    /\ \A c \in {c \in children_set : RestartType[c] = Temporary} :
         proc_state[c].state = Terminated \/ proc_state[sup].state = Terminated

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

IntensityEscalation ==
  \A sup \in {s \in Processes : IsSupervisor(s)} :
    (proc_state[sup].state = Running) =>
    (Len(restart_window[sup]) <= MaxR[sup])

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
====

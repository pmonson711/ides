---- MODULE SupervisorTree ----
EXTENDS Naturals, Sequences, FiniteSets, TLC

\* Process states
Running    == "running"
Terminated == "terminated"

ProcStateEnum == {Running, Terminated}

\* Restart strategies
OneForOne      == "one_for_one"
OneForAll      == "one_for_all"
RestForOne     == "rest_for_one"
SimpleOneForOne == "simple_one_for_one"

Strategies == {OneForOne, OneForAll, RestForOne, SimpleOneForOne}

\* Child restart types
Permanent == "permanent"
Transient == "transient"
Temporary == "temporary"

RestartTypes == {Permanent, Transient, Temporary}

\* Exit reasons
Normal   == "normal"
Abnormal == "abnormal"

ExitReasons == {Normal, Abnormal}

\* Process types
SupervisorType == "supervisor"
WorkerType     == "worker"

ProcTypes == {SupervisorType, WorkerType}

\* Constants — values supplied by TLC config
CONSTANTS Processes, Root, ChildrenOf, Strategy, RestartType, MaxR, MaxT, MaxClock

ASSUME Root \in Processes
ASSUME ChildrenOf \in [Processes -> Seq(Processes)]
ASSUME Strategy \in [Processes -> Strategies]
ASSUME RestartType \in [Processes -> RestartTypes]
ASSUME MaxR \in [Processes -> Nat]
ASSUME MaxT \in [Processes -> Nat]
ASSUME MaxClock \in Nat

\* --- Derived helpers ---

\* Convert a sequence to its set of elements
SeqToSet(seq) == {seq[i] : i \in 1..Len(seq)}

\* Position of an element in a sequence (1-indexed)
PositionOf(elem, seq) == CHOOSE i \in 1..Len(seq) : seq[i] = elem

\* True if p has non-empty children (i.e., is a supervisor)
IsSupervisor(p) == ChildrenOf[p] # <<>>

\* True if p has empty children (i.e., is a worker/leaf)
IsWorker(p) == ChildrenOf[p] = <<>>

\* Parent of p — the supervisor whose child list contains p.
\* Root is its own parent (sentinel). The tree well-formedness
\* invariant catches any misuse.
ParentOf(p) ==
  IF p = Root
  THEN Root
  ELSE CHOOSE sup \in Processes : p \in SeqToSet(ChildrenOf[sup])

\* All ancestors of p, not including p itself
AncestorsOf(p) ==
  LET Anc[pp \in Processes, acc \in SUBSET Processes] ==
    IF pp = Root THEN acc
    ELSE LET parent == ParentOf(pp)
         IN Anc[parent, acc \cup {parent}]
  IN Anc[p, {}]

\* Siblings of p (other children of the same supervisor)
SiblingsOf(p) == SeqToSet(ChildrenOf[ParentOf(p)]) \ {p}

\* Position of p among its parent's children
MyPosition(p) ==
  IF p = Root THEN 0
  ELSE PositionOf(p, ChildrenOf[ParentOf(p)])

\* Kill graph: all processes whose termination could cause P to die.
\*   - P's parent can always kill P
\*   - Under OneForAll, any sibling's death kills all siblings
\*   - Under RestForOne, any sibling at a lower index whose death
\*     triggers a cascade kills P
\*   - Under OneForOne / SimpleOneForOne, siblings don't affect each other
\*   - Any ancestor can kill P via restart-intensity escalation propagating down
KillGraph(P) ==
  LET sup       == ParentOf(P)
      strat     == Strategy[sup]
      ancestors == AncestorsOf(P)
      siblings  == SiblingsOf(P)
      pos       == MyPosition(P)
      killerSiblings ==
        CASE strat = OneForAll ->
          siblings
        [] strat = RestForOne ->
          siblings \intersect
          SeqToSet(SubSeq(ChildrenOf[sup], 1, pos - 1))
        [] OTHER ->
          {}
  IN ancestors \cup killerSiblings

\* Check if a terminated child should be restarted based on its
\* restart type and exit reason
ShouldRestart(child, ps) ==
  CASE RestartType[child] = Permanent -> TRUE
  [] RestartType[child] = Transient -> ps[child].exit = Abnormal
  [] OTHER -> FALSE

\* Count restarts for a supervisor within the current window
RestartCount(sup, rw, clk) ==
  LET threshold == IF clk > MaxT[sup] THEN clk - MaxT[sup] ELSE 0
  IN Cardinality({t \in SeqToSet(rw[sup]) : t > threshold})

\* Which children are affected when a supervisor reacts?
\*   terminated_set = the already-terminated children that triggered reaction
AffectedChildren(sup, terminated_set) ==
  CASE Strategy[sup] = OneForOne ->
    terminated_set
  [] Strategy[sup] = OneForAll ->
    SeqToSet(ChildrenOf[sup])
  [] Strategy[sup] = RestForOne ->
    LET children == ChildrenOf[sup]
        first_pos == CHOOSE c \in terminated_set : TRUE
    IN {children[i] : i \in PositionOf(first_pos, children) .. Len(children)}
  [] Strategy[sup] = SimpleOneForOne ->
    terminated_set

====

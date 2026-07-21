---- MODULE MCSimpleOneForOne ----
\* Simple-one-for-one supervisor: root with 2 workers
\*       root (simple_one_for_one)
\*      /    \
\*   child1  child2
\*   (perm)  (perm)

VARIABLES clock, proc_state, restart_window, history, monitor_down

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "child1", "child2"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "child1", "child2"} |-> CASE x = "root" -> <<"child1", "child2">> [] OTHER -> <<>>],
  Strategy    <- [x \in {"root", "child1", "child2"} |-> "simple_one_for_one"],
  RestartType <- [x \in {"root", "child1", "child2"} |-> "permanent"],
  MaxR        <- [x \in {"root", "child1", "child2"} |-> CASE x = "root" -> 1 [] OTHER -> 0],
  MaxT        <- [x \in {"root", "child1", "child2"} |-> CASE x = "root" -> 2 [] OTHER -> 0],
  MaxClock    <- 2,
  Links       <- [p \in {"root", "child1", "child2"} |-> {}],
  Monitors    <- [p \in {"root", "child1", "child2"} |-> {}],
  TrapsExits  <- [p \in {"root", "child1", "child2"} |-> FALSE],
  HandlesDown <- [p \in {"root", "child1", "child2"} |-> FALSE]
====

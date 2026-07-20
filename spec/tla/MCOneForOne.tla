---- MODULE MCOneForOne ----
\* One-for-one supervisor: root with 2 workers
\*       root (one_for_one)
\*      /    \
\*   child1  child2
\*   (perm)  (trans)

VARIABLES clock, proc_state, restart_window, history

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "child1", "child2"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "child1", "child2"} |-> CASE x = "root" -> <<"child1", "child2">> [] OTHER -> <<>>],
  Strategy    <- [x \in {"root", "child1", "child2"} |-> "one_for_one"],
  RestartType <- [x \in {"root", "child1", "child2"} |-> CASE x = "child2" -> "transient" [] OTHER -> "permanent"],
  MaxR        <- [x \in {"root", "child1", "child2"} |-> CASE x = "root" -> 1 [] OTHER -> 0],
  MaxT        <- [x \in {"root", "child1", "child2"} |-> CASE x = "root" -> 2 [] OTHER -> 0],
  MaxClock    <- 2
====

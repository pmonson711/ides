---- MODULE MCRestForOne ----
\* Rest-for-one supervisor: root with 3 workers
\*       root (rest_for_one)
\*      /    |    \
\*   child1 child2 child3
\*   (perm) (perm) (perm)

VARIABLES clock, proc_state, restart_window, history

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "child1", "child2", "child3"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "child1", "child2", "child3"} |-> CASE x = "root" -> <<"child1", "child2", "child3">> [] OTHER -> <<>>],
  Strategy    <- [x \in {"root", "child1", "child2", "child3"} |-> "rest_for_one"],
  RestartType <- [x \in {"root", "child1", "child2", "child3"} |-> "permanent"],
  MaxR        <- [x \in {"root", "child1", "child2", "child3"} |-> CASE x = "root" -> 2 [] OTHER -> 0],
  MaxT        <- [x \in {"root", "child1", "child2", "child3"} |-> CASE x = "root" -> 2 [] OTHER -> 0],
  MaxClock    <- 2
====

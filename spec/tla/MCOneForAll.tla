---- MODULE MCOneForAll ----
\* One-for-all supervisor: root with 3 workers
\*       root (one_for_all)
\*      /    |    \
\*   child1 child2 child3
\*   (perm) (perm) (temp)

VARIABLES clock, proc_state, restart_window, history, monitor_down

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "child1", "child2", "child3"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "child1", "child2", "child3"} |-> CASE x = "root" -> <<"child1", "child2", "child3">> [] OTHER -> <<>>],
  Strategy    <- [x \in {"root", "child1", "child2", "child3"} |-> "one_for_all"],
  RestartType <- [x \in {"root", "child1", "child2", "child3"} |-> CASE x = "child3" -> "temporary" [] OTHER -> "permanent"],
  MaxR        <- [x \in {"root", "child1", "child2", "child3"} |-> CASE x = "root" -> 1 [] OTHER -> 0],
  MaxT        <- [x \in {"root", "child1", "child2", "child3"} |-> CASE x = "root" -> 2 [] OTHER -> 0],
  MaxClock    <- 2,
  Links       <- [p \in {"root", "child1", "child2", "child3"} |-> {}],
  Monitors    <- [p \in {"root", "child1", "child2", "child3"} |-> {}],
  TrapsExits  <- [p \in {"root", "child1", "child2", "child3"} |-> FALSE],
  HandlesDown <- [p \in {"root", "child1", "child2", "child3"} |-> FALSE]
ASSUME KillGraphDeep
====

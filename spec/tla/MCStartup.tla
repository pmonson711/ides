---- MODULE MCStartup ----
\* Startup scenario: 1 supervisor with 5 children, MaxR=3, MaxT=5.
\* If 3+ children experience InitTimeout within the window, the
\* supervisor terminates (intensity exceeded).
\*
\* Process set:
\*   root (supervisor, one_for_one)
\*   child1..child5 (workers, permanent)
\*
\* We model startup as: all children start in Idle, StartChild
\* transitions them to Initing, then InitTimeout or InitSuccess.
\* MaxR=3 means 3 init timeouts -> supervisor death.

VARIABLES clock, proc_state, restart_window, history, monitor_down

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "child1", "child2", "child3", "child4", "child5"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "child1", "child2", "child3", "child4", "child5"} |->
                   CASE x = "root" -> <<"child1", "child2", "child3", "child4", "child5">>
                   [] OTHER -> <<>>],
  Strategy    <- [x \in {"root", "child1", "child2", "child3", "child4", "child5"} |-> "one_for_one"],
  RestartType <- [x \in {"root", "child1", "child2", "child3", "child4", "child5"} |-> "permanent"],
  MaxR        <- [x \in {"root", "child1", "child2", "child3", "child4", "child5"} |->
                   CASE x = "root" -> 3 [] OTHER -> 0],
  MaxT        <- [x \in {"root", "child1", "child2", "child3", "child4", "child5"} |->
                   CASE x = "root" -> 5 [] OTHER -> 0],
  MaxClock    <- 10,
  Links       <- [p \in {"root", "child1", "child2", "child3", "child4", "child5"} |-> {}],
  Monitors    <- [p \in {"root", "child1", "child2", "child3", "child4", "child5"} |-> {}],
  TrapsExits  <- [p \in {"root", "child1", "child2", "child3", "child4", "child5"} |-> FALSE],
  HandlesDown <- [p \in {"root", "child1", "child2", "child3", "child4", "child5"} |-> FALSE]
====

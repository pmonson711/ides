---- MODULE MCLinkKill ----
\* Link propagation: 3 workers all linked.
\*   p1 (traps exits) -- p2 (doesn't trap) -- p3 (doesn't trap)
\*   If p3 dies abnormally, p2 should die via link propagation.
\*   p1 should survive (traps exits, receives message).
\*
\* Kill graph for p2 should include: parent(p2), p3 (link killer)
\* Kill graph for p1 should include: parent(p1) only (traps exits)

VARIABLES clock, proc_state, restart_window, history, monitor_down

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "sup", "p1", "p2", "p3"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "sup", "p1", "p2", "p3"} |-> CASE x = "root" -> <<"sup">> [] x = "sup" -> <<"p1", "p2", "p3">> [] OTHER -> <<>>],
  Strategy    <- [x \in {"root", "sup", "p1", "p2", "p3"} |-> "one_for_one"],
  RestartType <- [x \in {"root", "sup", "p1", "p2", "p3"} |-> "permanent"],
  MaxR        <- [x \in {"root", "sup", "p1", "p2", "p3"} |-> CASE x = "sup" -> 3 [] OTHER -> 0],
  MaxT        <- [x \in {"root", "sup", "p1", "p2", "p3"} |-> CASE x = "sup" -> 10 [] OTHER -> 0],
  MaxClock    <- 10,
  Links       <- [x \in {"root", "sup", "p1", "p2", "p3"} |-> CASE x = "p1" -> {"p2", "p3"} [] x = "p2" -> {"p1", "p3"} [] x = "p3" -> {"p1", "p2"} [] OTHER -> {}],
  Monitors    <- [x \in {"root", "sup", "p1", "p2", "p3"} |-> {}],
  TrapsExits  <- [x \in {"root", "sup", "p1", "p2", "p3"} |-> CASE x = "p1" -> TRUE [] OTHER -> FALSE],
  HandlesDown <- [x \in {"root", "sup", "p1", "p2", "p3"} |-> FALSE]
ASSUME KillGraphDeep
====

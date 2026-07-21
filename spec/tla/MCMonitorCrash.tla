---- MODULE MCMonitorCrash ----
\* Monitor-based crashes: 3 workers, monitor chain.
\*   m1 monitors m2. m2 monitors m3.
\*   m1 handles DOWN. m2 does NOT handle DOWN.
\*   If m3 dies, m2 crashes (unhandled DOWN). m1 survives (handles DOWN).
\*
\* Kill graph for m2 should include: parent(m2), m3 (monitor killer)

VARIABLES clock, proc_state, restart_window, history, monitor_down

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "sup", "m1", "m2", "m3"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "sup", "m1", "m2", "m3"} |-> CASE x = "root" -> <<"sup">> [] x = "sup" -> <<"m1", "m2", "m3">> [] OTHER -> <<>>],
  Strategy    <- [x \in {"root", "sup", "m1", "m2", "m3"} |-> "one_for_one"],
  RestartType <- [x \in {"root", "sup", "m1", "m2", "m3"} |-> "permanent"],
  MaxR        <- [x \in {"root", "sup", "m1", "m2", "m3"} |-> CASE x = "sup" -> 3 [] OTHER -> 0],
  MaxT        <- [x \in {"root", "sup", "m1", "m2", "m3"} |-> CASE x = "sup" -> 10 [] OTHER -> 0],
  MaxClock    <- 10,
  Links       <- [x \in {"root", "sup", "m1", "m2", "m3"} |-> {}],
  Monitors    <- [x \in {"root", "sup", "m1", "m2", "m3"} |-> CASE x = "m1" -> {"m2"} [] x = "m2" -> {"m3"} [] OTHER -> {}],
  TrapsExits  <- [x \in {"root", "sup", "m1", "m2", "m3"} |-> FALSE],
  HandlesDown <- [x \in {"root", "sup", "m1", "m2", "m3"} |-> CASE x = "m1" -> TRUE [] OTHER -> FALSE]
ASSUME KillGraphDeep
====

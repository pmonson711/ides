---- MODULE MCNestedEscalation ----
\* Nested supervisors testing intensity escalation.
\*          root (one_for_one)
\*            |
\*          sup1 (one_for_all)
\*          /    \
\*       sub1   sub2   (both workers, permanent)

VARIABLES clock, proc_state, restart_window, history

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "sup1", "sub1", "sub2"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "sup1", "sub1", "sub2"} |-> CASE x = "root" -> <<"sup1">> [] x = "sup1" -> <<"sub1", "sub2">> [] OTHER -> <<>>],
  Strategy    <- [x \in {"root", "sup1", "sub1", "sub2"} |-> CASE x = "sup1" -> "one_for_all" [] OTHER -> "one_for_one"],
  RestartType <- [x \in {"root", "sup1", "sub1", "sub2"} |-> "permanent"],
  MaxR        <- [x \in {"root", "sup1", "sub1", "sub2"} |-> CASE x = "root" -> 2 [] x = "sup1" -> 1 [] OTHER -> 0],
  MaxT        <- [x \in {"root", "sup1", "sub1", "sub2"} |-> CASE x = "root" -> 2 [] x = "sup1" -> 2 [] OTHER -> 0],
  MaxClock    <- 2
====

---- MODULE MCNestedDeep3 ----
\* 3-level nested supervisors with mixed strategies.
\*
\*          root (one_for_one, MaxR=2, MaxT=5)
\*            |
\*          supA (one_for_all, MaxR=1, MaxT=3)
\*          /    \
\*       supB (rest_for_one, MaxR=1, MaxT=3)   worker3 (permanent)
\*       /    \
\*  worker1  worker2  (both permanent)
\*
\* Scenario: worker2 dies -> supB (rest_for_one) kills both workers,
\* restarts them -> supB exceeds intensity (MaxR=1) -> supB dies ->
\* supA (one_for_all) kills everything -> restarts.

VARIABLES clock, proc_state, restart_window, history

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "supA", "supB", "worker1", "worker2", "worker3"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "supA", "supB", "worker1", "worker2", "worker3"} |->
    CASE x = "root"  -> <<"supA">>
    [] x = "supA"    -> <<"supB", "worker3">>
    [] x = "supB"    -> <<"worker1", "worker2">>
    [] OTHER         -> <<>>],
  Strategy    <- [x \in {"root", "supA", "supB", "worker1", "worker2", "worker3"} |->
    CASE x = "supA"  -> "one_for_all"
    [] x = "supB"    -> "rest_for_one"
    [] OTHER         -> "one_for_one"],
  RestartType <- [x \in {"root", "supA", "supB", "worker1", "worker2", "worker3"} |-> "permanent"],
  MaxR        <- [x \in {"root", "supA", "supB", "worker1", "worker2", "worker3"} |->
    CASE x = "root"  -> 2
    [] x = "supA"    -> 1
    [] x = "supB"    -> 1
    [] OTHER         -> 0],
  MaxT        <- [x \in {"root", "supA", "supB", "worker1", "worker2", "worker3"} |->
    CASE x = "root"  -> 5
    [] x = "supA"    -> 3
    [] x = "supB"    -> 3
    [] OTHER         -> 0],
  MaxClock    <- 5
====

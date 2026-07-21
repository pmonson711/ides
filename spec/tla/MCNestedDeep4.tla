---- MODULE MCNestedDeep4 ----
\* 4-level nested supervisors, stress-testing deep cascade.
\*
\*       root (one_for_one, MaxR=2, MaxT=5)
\*         |
\*       supA (rest_for_one, MaxR=1, MaxT=3)
\*         |
\*       supB (one_for_all, MaxR=1, MaxT=3)
\*         |
\*       supC (one_for_one, MaxR=1, MaxT=3)
\*       /    \
\*  worker1  worker2  (both permanent)
\*
\* Scenario: worker1 dies -> supC restarts it -> supC exceeds
\* intensity -> supC dies -> supB (one_for_all) kills all ->
\* supB exceeds -> supB dies -> supA (rest_for_one) cascades ->
\* supA exceeds -> supA dies -> root restarts everything.

VARIABLES clock, proc_state, restart_window, history, monitor_down

INSTANCE SupervisorModel WITH
  Processes   <- {"root", "supA", "supB", "supC", "worker1", "worker2"},
  Root        <- "root",
  ChildrenOf  <- [x \in {"root", "supA", "supB", "supC", "worker1", "worker2"} |->
    CASE x = "root"  -> <<"supA">>
    [] x = "supA"    -> <<"supB">>
    [] x = "supB"    -> <<"supC">>
    [] x = "supC"    -> <<"worker1", "worker2">>
    [] OTHER         -> <<>>],
  Strategy    <- [x \in {"root", "supA", "supB", "supC", "worker1", "worker2"} |->
    CASE x = "supA"  -> "rest_for_one"
    [] x = "supB"    -> "one_for_all"
    [] x = "supC"    -> "one_for_one"
    [] OTHER         -> "one_for_one"],
  RestartType <- [x \in {"root", "supA", "supB", "supC", "worker1", "worker2"} |-> "permanent"],
  MaxR        <- [x \in {"root", "supA", "supB", "supC", "worker1", "worker2"} |->
    CASE x = "root"  -> 2
    [] x = "supA"    -> 1
    [] x = "supB"    -> 1
    [] x = "supC"    -> 1
    [] OTHER         -> 0],
  MaxT        <- [x \in {"root", "supA", "supB", "supC", "worker1", "worker2"} |->
    CASE x = "root"  -> 5
    [] x = "supA"    -> 3
    [] x = "supB"    -> 3
    [] x = "supC"    -> 3
    [] OTHER         -> 0],
  MaxClock    <- 5,
  Links       <- [p \in {"root", "supA", "supB", "supC", "worker1", "worker2"} |-> {}],
  Monitors    <- [p \in {"root", "supA", "supB", "supC", "worker1", "worker2"} |-> {}],
  TrapsExits  <- [p \in {"root", "supA", "supB", "supC", "worker1", "worker2"} |-> FALSE],
  HandlesDown <- [p \in {"root", "supA", "supB", "supC", "worker1", "worker2"} |-> FALSE]
====

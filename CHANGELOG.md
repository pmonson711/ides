## [0.4.2] - 2026-08-03

### 🚀 Features

- Define ides module API, types, and exports
- Implement format/2 with indented tree rendering
- Implement $ancestors extraction with error handling
- Implement supervisor tree walking with strategy and restart type
- Implement supervisor tree walking with strategy and restart type
- Add kill_graph, should_restart, affected_siblings covering TLA+ properties
- Add example app skeleton (rebar.config, app.src, demo.erl)
- Add demo_sup one_for_one top supervisor
- Add leaf gen_servers (cache, metrics, router, auth, api, logger)
- Add demo_db_pool simple_one_for_one supervisor and worker
- Add demo_web_sup rest_for_one supervisor
- Add demo_handler_sup one_for_all supervisor
- Init timeout analysis and startup intensity escalation (#15)

### 🐛 Bug Fixes

- Add restart_type to supervisor_process type as optional key
- Use process_info for supervisor detection, preserve child supervisor name
- Resolve all eqwalizer type errors
- Make rest_for_one kill_graph tests order-agnostic
- Use relative refernce checkout for demo_app

### 💼 Other

- Move KillGraphDeep from INVARIANTS to ASSUME (constant-level formula) (#12)

### 🚜 Refactor

- Split into ides, ides_family, ides_printer, ides_march modules

### 📚 Documentation

- Add kill_graph, should_restart, affected_siblings to README
- Replace -doc attributes with EDoc comments in source
- Use per-function -doc attributes (EEP59) instead of EDoc comments
- Drop inline API from README, fix ex_doc extras config, gitignore doc/
- Why not kill the pid? (draft) (#7)
- Add TLA+ spec documentation (#16)

### 🧪 Testing

- Add EUnit test skeleton for ides
- Add end-to-end topology verification tests
- Add demo_arch_SUITE for supervision architecture assertions
- Add demo_kill_graph_SUITE for cascade and isolation assertions

### ⚙️ Miscellaneous Tasks

- Include hex integration
- Add .worktrees/ to .gitignore
- Clean up docs and xref
- Reformat cfg files (#11)

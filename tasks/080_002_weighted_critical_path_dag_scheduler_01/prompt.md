Write me an Elixir module called `WeightedDAG` that implements a **weighted** Directed Acyclic Graph used for **project / task scheduling**. It should be a pure data structure (no GenServer), where each function takes and returns a `WeightedDAG` struct (or a result tuple).

Unlike a plain topological sort, this graph attaches a **non-negative duration** to each task (vertex) and answers scheduling questions: earliest start times, the total project makespan, and the **critical path** (the longest-duration chain of dependent tasks).

I need these functions in the public API:
- `WeightedDAG.new()` — returns an empty graph.
- `WeightedDAG.add_task(dag, id, duration)` — adds a task vertex `id` with a non-negative numeric `duration`. If the task already exists, return the dag unchanged (keep the original duration). Task ids can be any term.
- `WeightedDAG.add_dependency(dag, from, to)` — adds a directed dependency edge meaning "`from` must finish before `to` starts". Both tasks must already exist. If the edge would create a cycle, return `{:error, :cycle}`. On success return `{:ok, new_dag}`. Cycle detection must be **eager** (DFS-based) in `add_dependency/3`.
- `WeightedDAG.topological_sort(dag)` — returns `{:ok, ordering}` (Kahn's algorithm, BFS over in-degrees). `{:ok, []}` for an empty graph.
- `WeightedDAG.earliest_start(dag)` — returns `{:ok, map}` where `map` is `%{id => earliest_start_time}`. A task's earliest start is the maximum over its direct predecessors of `(predecessor's earliest start + predecessor's duration)`, or `0` if it has no predecessors.
- `WeightedDAG.earliest_finish(dag)` — returns `{:ok, map}` where each value is `earliest_start + duration`.
- `WeightedDAG.makespan(dag)` — returns `{:ok, number}`, the total project duration = the maximum earliest-finish over all tasks (`{:ok, 0}` for an empty graph).
- `WeightedDAG.critical_path(dag)` — returns `{:ok, path}` where `path` is a list of task ids forming a longest-duration path from a source task to a sink task (the chain that determines the makespan). `{:ok, []}` for an empty graph. Break ties deterministically (prefer the smallest task id by term ordering).
- `WeightedDAG.predecessors(dag, id)` / `WeightedDAG.successors(dag, id)` — direct incoming / outgoing neighbours, returned as a plain list of task ids (not a result tuple), sorted ascending by term ordering; `[]` for a task with no such neighbours.

Give me the complete module in a single file. Use only the Elixir/Erlang standard library, no external dependencies.
# Design Brief: `WeightedDAG` — a scheduling graph for Elixir

## Problem

Project and task scheduling needs more than a plain topological sort. Given a set of tasks with dependencies between them, we need to answer *when* things can start, *how long* the whole project takes, and *which* chain of tasks is the bottleneck.

I need an Elixir module called `WeightedDAG` that implements a **weighted** Directed Acyclic Graph used for **project / task scheduling**. Unlike a plain topological sort, this graph attaches a **non-negative duration** to each task (vertex) and answers scheduling questions: earliest start times, the total project makespan, and the **critical path** (the longest-duration chain of dependent tasks).

## Constraints

- It must be a pure data structure — **no GenServer**. Each function takes and returns a `WeightedDAG` struct (or a result tuple).
- Task ids can be any term.
- Cycle detection must be **eager** (DFS-based) in `add_dependency/3`.
- `topological_sort/1` must use Kahn's algorithm (BFS over in-degrees).
- Use only the Elixir/Erlang standard library, no external dependencies.
- Deliver the complete module in a single file.

## Required public API

1. `WeightedDAG.new()` — returns an empty graph.
2. `WeightedDAG.add_task(dag, id, duration)` — adds a task vertex `id` with a non-negative numeric `duration`. If the task already exists, return the dag unchanged (keep the original duration).
3. `WeightedDAG.add_dependency(dag, from, to)` — adds a directed dependency edge meaning "`from` must finish before `to` starts". Both tasks must already exist. If the edge would create a cycle, return `{:error, :cycle}`. On success return `{:ok, new_dag}`.
4. `WeightedDAG.topological_sort(dag)` — returns `{:ok, ordering}`. `{:ok, []}` for an empty graph.
5. `WeightedDAG.earliest_start(dag)` — returns `{:ok, map}` where `map` is `%{id => earliest_start_time}`. A task's earliest start is the maximum over its direct predecessors of `(predecessor's earliest start + predecessor's duration)`, or `0` if it has no predecessors.
6. `WeightedDAG.earliest_finish(dag)` — returns `{:ok, map}` where each value is `earliest_start + duration`.
7. `WeightedDAG.makespan(dag)` — returns `{:ok, number}`, the total project duration = the maximum earliest-finish over all tasks (`{:ok, 0}` for an empty graph).
8. `WeightedDAG.critical_path(dag)` — returns `{:ok, path}` where `path` is a list of task ids forming a longest-duration path from a source task to a sink task (the chain that determines the makespan). `{:ok, []}` for an empty graph. Break ties deterministically (prefer the smallest task id by term ordering).
9. `WeightedDAG.predecessors(dag, id)` / `WeightedDAG.successors(dag, id)` — direct incoming / outgoing neighbours, returned as a plain list of task ids (not a result tuple), sorted ascending by term ordering; `[]` for a task with no such neighbours.

## Acceptance criteria

- Every function above is present in the public API with the stated arity and return shape.
- Adding a duplicate task is a no-op that preserves the original duration.
- `add_dependency/3` rejects cycles eagerly with `{:error, :cycle}` and otherwise returns `{:ok, new_dag}`; both endpoints must already exist.
- Empty-graph cases return `{:ok, []}` for `topological_sort/1` and `critical_path/1`, and `{:ok, 0}` for `makespan/1`.
- Earliest-start, earliest-finish, and makespan values follow the definitions above exactly.
- `critical_path/1` is deterministic under ties, preferring the smallest task id by term ordering.
- `predecessors/2` and `successors/2` return bare sorted lists, not result tuples.
- The module is self-contained in one file, standard library only, with no process state.

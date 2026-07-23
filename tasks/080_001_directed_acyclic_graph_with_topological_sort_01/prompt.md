# Design brief: `DAG` — a directed acyclic graph with topological sorting

## Problem

I need a way to model dependency relationships in Elixir: a Directed Acyclic Graph that can tell me, at any point, a valid order in which to process its vertices. The graph must reject any edge that would introduce a cycle at the moment the edge is added, so the structure is never in an invalid state.

## Constraints

- Deliver an Elixir module called `DAG`.
- It must be a pure data structure — **no GenServer**. Each function takes and returns a DAG struct.
- Vertices can be any term.
- Cycle detection must happen eagerly in `add_edge/3` — do not defer it to sort time.
- Use DFS-based cycle detection.
- For topological sort, use Kahn's algorithm (BFS-based, iterating over in-degrees).
- Use only the Elixir/Erlang standard library, no external dependencies.
- Deliver the complete module in a single file.

## Required public interface

1. `DAG.new()` — returns an empty DAG struct.
2. `DAG.add_vertex(dag, vertex)` — adds a vertex to the graph; if it already exists, return the dag unchanged.
3. `DAG.add_edge(dag, from, to)` — adds a directed edge from `from` to `to`. Both vertices must already exist. If either vertex does not already exist, return an error tuple rather than `{:ok, _}`, leaving the graph unchanged. If the edge would create a cycle, return `{:error, :cycle}`. On success, return `{:ok, new_dag}`.
4. `DAG.topological_sort(dag)` — returns `{:ok, ordering}` where `ordering` is a list of all vertices in a valid topological order (every vertex appears before all of its dependents). If the graph is empty, return `{:ok, []}`.
5. `DAG.predecessors(dag, vertex)` — returns the list of vertices that have a direct edge pointing **to** the given vertex (i.e. its direct dependencies).
6. `DAG.successors(dag, vertex)` — returns the list of vertices that the given vertex has a direct edge pointing **to** (i.e. what directly depends on it).

## Acceptance criteria

- All six functions above are present in the public API and behave exactly as described.
- Adding a duplicate vertex leaves the dag unchanged.
- `add_edge/3` with a missing `from` or `to` vertex yields an error tuple (not `{:ok, _}`) and the graph is unmodified.
- `add_edge/3` that would close a cycle yields `{:error, :cycle}`; a successful add yields `{:ok, new_dag}`.
- `topological_sort/1` on an empty graph yields `{:ok, []}`; otherwise `{:ok, ordering}` covering all vertices with every vertex ahead of all of its dependents.
- Cycle checking is done at edge-insertion time via DFS; ordering is produced via Kahn's algorithm over in-degrees.
- The whole thing lives in one file and depends on nothing outside the Elixir/Erlang standard library.

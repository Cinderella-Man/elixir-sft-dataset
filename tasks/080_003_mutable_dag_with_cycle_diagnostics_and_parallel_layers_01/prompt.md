Write me an Elixir module called `MutableDAG` that implements a Directed Acyclic Graph supporting **mutation** (edge and vertex removal), **cycle diagnostics** (reporting the actual offending cycle path), and **parallel-execution layers**. It should be a pure data structure (no GenServer), where each function takes and returns a `MutableDAG` struct (or a result tuple).

I need these functions in the public API:
- `MutableDAG.new()` — returns an empty DAG.
- `MutableDAG.add_vertex(dag, vertex)` — adds a vertex; if it already exists, return the dag unchanged. Vertices can be any term.
- `MutableDAG.add_edge(dag, from, to)` — adds a directed edge. Both vertices must exist. If the edge would create a cycle, return `{:error, {:cycle, path}}` where `path` is the list of vertices forming the cycle, **starting and ending with `from`** (e.g. adding `c -> a` when `a -> b -> c` already exists returns `{:error, {:cycle, [c, a, b, c]}}`). A self-loop `add_edge(dag, a, a)` returns `{:error, {:cycle, [a, a]}}`. On success return `{:ok, new_dag}`. Detection must be eager (DFS path search).
- `MutableDAG.remove_edge(dag, from, to)` — removes the directed edge if present; if the edge or either vertex is absent, return the dag unchanged.
- `MutableDAG.remove_vertex(dag, vertex)` — removes the vertex and every edge incident to it (both incoming and outgoing); if absent, return the dag unchanged.
- `MutableDAG.topological_sort(dag)` — returns `{:ok, ordering}`, a flat list of all vertices in a valid topological order. `{:ok, []}` for an empty graph.
- `MutableDAG.topological_layers(dag)` — returns `{:ok, layers}` where `layers` is a list of lists. Layer 0 contains every vertex with no predecessors; each subsequent layer contains the vertices whose predecessors have all appeared in earlier layers. This groups vertices into "waves" that could execute in parallel. Sort the vertices **within each layer** by term ordering for determinism. `{:ok, []}` for an empty graph.
- `MutableDAG.predecessors(dag, vertex)` / `MutableDAG.successors(dag, vertex)` — direct incoming / outgoing neighbours.

Give me the complete module in a single file. Use only the Elixir/Erlang standard library, no external dependencies.
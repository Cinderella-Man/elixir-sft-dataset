Hey — I need a piece of graph plumbing built and I'd rather describe it than write it myself, so here's exactly what I'm after.

I want an Elixir module called `MutableDAG`: a Directed Acyclic Graph that supports **mutation** (removing edges and vertices), **cycle diagnostics** (it has to tell me the actual offending cycle path, not just "nope"), and **parallel-execution layers**. Keep it a pure data structure — no GenServer anywhere. Every function takes a `MutableDAG` struct and hands back a `MutableDAG` struct (or a result tuple).

The public API I'm counting on:

`MutableDAG.new()` — gives me an empty DAG.

`MutableDAG.add_vertex(dag, vertex)` — adds a vertex; if it's already in there, just return the dag unchanged. Vertices can be any term, so don't constrain them.

`MutableDAG.add_edge(dag, from, to)` — adds a directed edge. Both vertices have to exist already. If the edge would create a cycle, I want `{:error, {:cycle, path}}` back, where `path` is the list of vertices making up the cycle, **starting and ending with `from`** — so if `a -> b -> c` is already in the graph and I try to add `c -> a`, I expect `{:error, {:cycle, [c, a, b, c]}}`. A self-loop, `add_edge(dag, a, a)`, should come back as `{:error, {:cycle, [a, a]}}`. When it works, return `{:ok, new_dag}`. The detection needs to be eager — do a DFS path search at insert time.

`MutableDAG.remove_edge(dag, from, to)` — drops the directed edge if it's there; if the edge is missing, or either vertex is missing, return the dag unchanged.

`MutableDAG.remove_vertex(dag, vertex)` — removes the vertex along with every edge incident to it, both incoming and outgoing; if the vertex isn't present, return the dag unchanged.

`MutableDAG.topological_sort(dag)` — returns `{:ok, ordering}`, a flat list of all the vertices in a valid topological order. An empty graph gives `{:ok, []}`.

`MutableDAG.topological_layers(dag)` — returns `{:ok, layers}`, where `layers` is a list of lists. Layer 0 holds every vertex with no predecessors; each layer after that holds the vertices whose predecessors have all already shown up in earlier layers. That's the grouping I want — "waves" of vertices that could run in parallel. Sort the vertices **within each layer** by term ordering so the output is deterministic. Empty graph gives `{:ok, []}`.

`MutableDAG.predecessors(dag, vertex)` and `MutableDAG.successors(dag, vertex)` — the direct incoming and outgoing neighbours respectively.

One more bit of the interface contract I care about: `add_edge(dag, from, to)` must return exactly `{:error, :vertex_not_found}` when either endpoint (`from` or `to`) hasn't been added as a vertex.

Please send me the complete module in a single file, and stick to the Elixir/Erlang standard library — no external dependencies.

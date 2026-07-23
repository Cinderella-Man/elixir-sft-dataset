# `DAGServer` — process-based DAG registry

Implement an Elixir module `DAGServer`: a Directed Acyclic Graph backed by a **GenServer**. The graph lives in the server's state; all mutations are serialized through the single server process so many client processes can add vertices and edges concurrently and safely.

**Client API** (every function takes the server pid or name as the first argument)

- `DAGServer.start_link(opts \\ [])` — starts the server with an empty graph. `opts` are passed through to `GenServer.start_link/3` (e.g. `:name`). Returns `{:ok, pid}`.
- `DAGServer.add_vertex(server, vertex)` — adds a vertex. No change if it already exists. Returns `:ok`. Vertices may be any term.
- `DAGServer.add_edge(server, from, to)` — adds a directed edge. Returns `:ok` on success; `{:error, :cycle}` if the edge would create a cycle; `{:error, :vertex_not_found}` if either endpoint is missing.
- `DAGServer.topological_sort(server)` — returns `{:ok, ordering}` containing all vertices in a valid topological order. Returns `{:ok, []}` when the graph is empty.
- `DAGServer.predecessors(server, vertex)` — list of direct incoming neighbours.
- `DAGServer.successors(server, vertex)` — list of direct outgoing neighbours.
- `DAGServer.vertices(server)` — list of all vertices currently in the graph.

**Algorithms**

- Topological sort: Kahn's algorithm.
- Edge cycle detection: DFS-based, evaluated eagerly — before the edge is committed.

**Concurrency**

- Writes pass through the single GenServer process; concurrent `add_vertex`/`add_edge` calls from many processes must be applied consistently.
- The graph must remain acyclic at all times.

**Deliverable**

- Complete module in a single file.
- Elixir/Erlang standard library only; no external dependencies.

Write me an Elixir module called `DAGServer` that implements a Directed Acyclic Graph as a **GenServer** — a concurrent, process-based registry that holds the graph in its state and serializes all mutations so many client processes can safely add vertices and edges at once.

I need this client-facing API (all functions take the server pid or name as the first argument):
- `DAGServer.start_link(opts \\ [])` — starts the server (empty graph). `opts` are passed through to `GenServer.start_link/3` (e.g. `:name`). Returns `{:ok, pid}`.
- `DAGServer.add_vertex(server, vertex)` — adds a vertex; if it already exists, no change. Returns `:ok`. Vertices can be any term.
- `DAGServer.add_edge(server, from, to)` — adds a directed edge. Returns `:ok` on success, `{:error, :cycle}` if the edge would create a cycle (detected eagerly via DFS, before committing), or `{:error, :vertex_not_found}` if either endpoint is missing.
- `DAGServer.topological_sort(server)` — returns `{:ok, ordering}`, all vertices in a valid topological order (Kahn's algorithm). `{:ok, []}` when empty.
- `DAGServer.predecessors(server, vertex)` — direct incoming neighbours (list).
- `DAGServer.successors(server, vertex)` — direct outgoing neighbours (list).
- `DAGServer.vertices(server)` — the list of all vertices currently in the graph.

Because writes go through the single GenServer process, concurrent `add_vertex`/`add_edge` calls from many processes must be applied consistently and the graph must remain acyclic at all times. Use Kahn's algorithm for the sort and DFS-based cycle detection for edges.

Give me the complete module in a single file. Use only the Elixir/Erlang standard library, no external dependencies.
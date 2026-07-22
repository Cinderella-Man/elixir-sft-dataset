Write me an Elixir module called `DAG` that implements a Directed Acyclic Graph with topological sorting. It should be a pure data structure (no GenServer), where each function takes and returns a DAG struct.

I need these functions in the public API:
- `DAG.new()` — returns an empty DAG struct
- `DAG.add_vertex(dag, vertex)` — adds a vertex to the graph; if it already exists, return the dag unchanged. Vertices can be any term.
- `DAG.add_edge(dag, from, to)` — adds a directed edge from `from` to `to`. Both vertices must already exist. If the edge would create a cycle, return `{:error, :cycle}`. On success, return `{:ok, new_dag}`.
- `DAG.topological_sort(dag)` — returns `{:ok, ordering}` where `ordering` is a list of all vertices in a valid topological order (every vertex appears before all of its dependents). If the graph is empty, return `{:ok, []}`.
- `DAG.predecessors(dag, vertex)` — returns the list of vertices that have a direct edge pointing **to** the given vertex (i.e. its direct dependencies).
- `DAG.successors(dag, vertex)` — returns the list of vertices that the given vertex has a direct edge pointing **to** (i.e. what directly depends on it).

Cycle detection must happen eagerly in `add_edge/3` — do not defer it to sort time. Use DFS-based cycle detection. For topological sort, use Kahn's algorithm (BFS-based, iterating over in-degrees).

Give me the complete module in a single file. Use only the Elixir/Erlang standard library, no external dependencies.
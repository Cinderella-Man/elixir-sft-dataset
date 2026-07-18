# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `add_edge` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `add_edge` missing

```elixir
defmodule DAGServer do
  @moduledoc """
  A Directed Acyclic Graph implemented as a GenServer.

  The graph lives in the process state; all mutations are serialized through
  the single server process, so any number of client processes may add
  vertices and edges concurrently while the graph remains consistent and
  acyclic at all times.

  State fields:
    * `vertices`  – a `MapSet` of all vertices (any term).
    * `out_edges` – `%{vertex => MapSet of successors}` (forward adjacency).
    * `in_edges`  – `%{vertex => MapSet of predecessors}` (reverse adjacency).
  """

  use GenServer

  defstruct vertices: MapSet.new(), out_edges: %{}, in_edges: %{}

  @typedoc "The internal graph state held by the server process."
  @type t :: %__MODULE__{
          vertices: MapSet.t(),
          out_edges: %{optional(term()) => MapSet.t()},
          in_edges: %{optional(term()) => MapSet.t()}
        }

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the server with an empty graph.

  `opts` are forwarded to `GenServer.start_link/3` (e.g. `:name`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Adds `vertex` to the graph. If it already exists, the graph is unchanged.

  Vertices may be any term. Returns `:ok`.
  """
  @spec add_vertex(GenServer.server(), term()) :: :ok
  def add_vertex(server, vertex), do: GenServer.call(server, {:add_vertex, vertex})

  @doc """
  Adds a directed edge from `from` to `to`.

  Returns `:ok` on success, `{:error, :cycle}` if the edge would create a
  cycle (detected eagerly via DFS before committing), or
  `{:error, :vertex_not_found}` if either endpoint is missing.
  """
  @spec add_edge(GenServer.server(), term(), term()) ::
          :ok | {:error, :cycle | :vertex_not_found}
  def add_edge(server, from, to) do
    # TODO
  end

  @doc """
  Returns `{:ok, ordering}` with all vertices in a valid topological order
  (Kahn's algorithm). Returns `{:ok, []}` when the graph is empty.
  """
  @spec topological_sort(GenServer.server()) :: {:ok, [term()]}
  def topological_sort(server), do: GenServer.call(server, :topological_sort)

  @doc """
  Returns the list of direct incoming neighbours (predecessors) of `vertex`.
  """
  @spec predecessors(GenServer.server(), term()) :: [term()]
  def predecessors(server, vertex), do: GenServer.call(server, {:predecessors, vertex})

  @doc """
  Returns the list of direct outgoing neighbours (successors) of `vertex`.
  """
  @spec successors(GenServer.server(), term()) :: [term()]
  def successors(server, vertex), do: GenServer.call(server, {:successors, vertex})

  @doc """
  Returns the list of all vertices currently in the graph.
  """
  @spec vertices(GenServer.server()) :: [term()]
  def vertices(server), do: GenServer.call(server, :vertices)

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @doc false
  @impl true
  @spec init(:ok) :: {:ok, t()}
  def init(:ok), do: {:ok, %__MODULE__{}}

  @doc false
  @impl true
  @spec handle_call(term(), GenServer.from(), t()) :: {:reply, term(), t()}
  def handle_call({:add_vertex, vertex}, _from, state) do
    {:reply, :ok, do_add_vertex(state, vertex)}
  end

  def handle_call({:add_edge, from, to}, _from, state) do
    case do_add_edge(state, from, to) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:topological_sort, _from, state) do
    {:reply, {:ok, topo_order(state)}, state}
  end

  def handle_call({:predecessors, vertex}, _from, state) do
    {:reply, state.in_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list(), state}
  end

  def handle_call({:successors, vertex}, _from, state) do
    {:reply, state.out_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list(), state}
  end

  def handle_call(:vertices, _from, state) do
    {:reply, MapSet.to_list(state.vertices), state}
  end

  # ---------------------------------------------------------------------------
  # Pure graph logic
  # ---------------------------------------------------------------------------

  defp do_add_vertex(state, vertex) do
    if MapSet.member?(state.vertices, vertex) do
      state
    else
      %{
        state
        | vertices: MapSet.put(state.vertices, vertex),
          out_edges: Map.put_new(state.out_edges, vertex, MapSet.new()),
          in_edges: Map.put_new(state.in_edges, vertex, MapSet.new())
      }
    end
  end

  defp do_add_edge(state, from, to) do
    with :ok <- require_vertex(state, from),
         :ok <- require_vertex(state, to),
         :ok <- check_no_cycle(state, from, to) do
      new_state = %{
        state
        | out_edges: Map.update!(state.out_edges, from, &MapSet.put(&1, to)),
          in_edges: Map.update!(state.in_edges, to, &MapSet.put(&1, from))
      }

      {:ok, new_state}
    end
  end

  defp require_vertex(state, vertex) do
    if MapSet.member?(state.vertices, vertex), do: :ok, else: {:error, :vertex_not_found}
  end

  defp check_no_cycle(_state, from, from), do: {:error, :cycle}

  defp check_no_cycle(state, from, to) do
    if dfs_reaches?(state.out_edges, to, from), do: {:error, :cycle}, else: :ok
  end

  defp dfs_reaches?(out_edges, start, target) do
    do_dfs([start], MapSet.new(), out_edges, target)
  end

  defp do_dfs([], _visited, _out_edges, _target), do: false

  defp do_dfs([node | stack], visited, out_edges, target) do
    cond do
      node == target ->
        true

      MapSet.member?(visited, node) ->
        do_dfs(stack, visited, out_edges, target)

      true ->
        neighbors = out_edges |> Map.get(node, MapSet.new()) |> MapSet.to_list()
        do_dfs(neighbors ++ stack, MapSet.put(visited, node), out_edges, target)
    end
  end

  # Kahn's algorithm, sorted for determinism.
  defp topo_order(state) do
    in_degree =
      Map.new(state.vertices, fn v -> {v, MapSet.size(Map.fetch!(state.in_edges, v))} end)

    initial =
      in_degree
      |> Enum.filter(fn {_v, d} -> d == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    kahn(initial, in_degree, state.out_edges, [])
  end

  defp kahn([], _in_degree, _out_edges, acc), do: Enum.reverse(acc)

  defp kahn([v | rest], in_degree, out_edges, acc) do
    {new_in_degree, newly_zero} =
      out_edges
      |> Map.fetch!(v)
      |> Enum.reduce({in_degree, []}, fn succ, {deg_map, zeros} ->
        new_deg = Map.fetch!(deg_map, succ) - 1
        updated = Map.put(deg_map, succ, new_deg)

        if new_deg == 0, do: {updated, [succ | zeros]}, else: {updated, zeros}
      end)

    kahn(rest ++ Enum.sort(newly_zero), new_in_degree, out_edges, [v | acc])
  end
end
```

Give me only the complete implementation of `add_edge` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.

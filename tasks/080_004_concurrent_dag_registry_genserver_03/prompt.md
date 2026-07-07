# Fill in the middle: `kahn/4`

The `DAGServer` module below is complete **except** for the private helper
`kahn/4`, which drives Kahn's algorithm for `topological_sort/1`.

Implement the private `kahn/4` function. It is the recursive worker of Kahn's
algorithm and has two clauses.

`kahn/4` takes four arguments:
  1. a list of vertices whose in-degree is currently `0` (the "ready" queue,
     kept sorted for deterministic output),
  2. `in_degree` — a map of `%{vertex => remaining in-degree}`,
  3. `out_edges` — the forward adjacency map `%{vertex => MapSet of successors}`,
  4. `acc` — the ordering accumulated so far, in **reverse** order.

Behaviour:
  * **Base clause** — when the ready queue is empty, the sort is done: return
    `acc` reversed (i.e. `Enum.reverse(acc)`) to yield the vertices in
    topological order.
  * **Recursive clause** — take the head `v` off the ready queue. For each of
    `v`'s successors (look them up in `out_edges` with `Map.fetch!/2`),
    decrement that successor's count in `in_degree` by 1; any successor whose
    new count reaches `0` becomes newly ready. Then recurse with:
      - the rest of the queue followed by the newly-zero vertices **sorted**
        (`rest ++ Enum.sort(newly_zero)`) so output is deterministic,
      - the updated `in_degree` map,
      - the unchanged `out_edges`,
      - `v` prepended onto `acc`.

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
  def add_edge(server, from, to), do: GenServer.call(server, {:add_edge, from, to})

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

  defp kahn([], _in_degree, _out_edges, acc) do
    # TODO
  end

  defp kahn([v | rest], in_degree, out_edges, acc) do
    # TODO
  end
end
```
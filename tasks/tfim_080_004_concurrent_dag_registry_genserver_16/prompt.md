# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule DAGServerTest do
  use ExUnit.Case, async: false

  defp valid_topological_order?(ordering, edges) do
    index = ordering |> Enum.with_index() |> Map.new()

    Enum.all?(edges, fn {from, to} ->
      Map.fetch!(index, from) < Map.fetch!(index, to)
    end)
  end

  setup do
    {:ok, pid} = DAGServer.start_link()
    {:ok, server: pid}
  end

  # -------------------------------------------------------
  # Basic behaviour
  # -------------------------------------------------------

  test "empty graph sorts to []", %{server: s} do
    assert {:ok, []} = DAGServer.topological_sort(s)
    assert DAGServer.vertices(s) == []
  end

  test "add_vertex is idempotent", %{server: s} do
    assert :ok = DAGServer.add_vertex(s, :a)
    assert :ok = DAGServer.add_vertex(s, :a)
    assert :ok = DAGServer.add_vertex(s, :b)
    assert Enum.sort(DAGServer.vertices(s)) == [:a, :b]
  end

  test "add_edge success and linear sort", %{server: s} do
    :ok = DAGServer.add_vertex(s, :a)
    :ok = DAGServer.add_vertex(s, :b)
    :ok = DAGServer.add_vertex(s, :c)
    assert :ok = DAGServer.add_edge(s, :a, :b)
    assert :ok = DAGServer.add_edge(s, :b, :c)
    assert {:ok, [:a, :b, :c]} = DAGServer.topological_sort(s)
  end

  # -------------------------------------------------------
  # Error semantics
  # -------------------------------------------------------

  test "missing vertex is rejected", %{server: s} do
    :ok = DAGServer.add_vertex(s, :a)
    assert {:error, :vertex_not_found} = DAGServer.add_edge(s, :a, :ghost)
  end

  test "self-loop and direct cycle rejected", %{server: s} do
    :ok = DAGServer.add_vertex(s, :a)
    :ok = DAGServer.add_vertex(s, :b)
    assert {:error, :cycle} = DAGServer.add_edge(s, :a, :a)
    :ok = DAGServer.add_edge(s, :a, :b)
    assert {:error, :cycle} = DAGServer.add_edge(s, :b, :a)
  end

  test "indirect cycle rejected", %{server: s} do
    for v <- [:a, :b, :c], do: :ok = DAGServer.add_vertex(s, v)
    :ok = DAGServer.add_edge(s, :a, :b)
    :ok = DAGServer.add_edge(s, :b, :c)
    assert {:error, :cycle} = DAGServer.add_edge(s, :c, :a)
  end

  # -------------------------------------------------------
  # Neighbours
  # -------------------------------------------------------

  test "predecessors and successors", %{server: s} do
    for v <- [:a, :b, :c], do: :ok = DAGServer.add_vertex(s, v)
    :ok = DAGServer.add_edge(s, :a, :c)
    :ok = DAGServer.add_edge(s, :b, :c)
    assert Enum.sort(DAGServer.predecessors(s, :c)) == [:a, :b]
    assert DAGServer.successors(s, :a) == [:c]
    assert DAGServer.successors(s, :c) == []
  end

  # -------------------------------------------------------
  # Concurrency
  # -------------------------------------------------------

  test "concurrent add_vertex from many processes lands consistently", %{server: s} do
    1..100
    |> Enum.map(fn i -> Task.async(fn -> DAGServer.add_vertex(s, i) end) end)
    |> Enum.each(&Task.await/1)

    assert Enum.sort(DAGServer.vertices(s)) == Enum.to_list(1..100)
  end

  test "concurrent chain edges stay acyclic and consistent", %{server: s} do
    for i <- 1..50, do: :ok = DAGServer.add_vertex(s, i)

    results =
      1..49
      |> Enum.map(fn i -> Task.async(fn -> DAGServer.add_edge(s, i, i + 1) end) end)
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == :ok))

    {:ok, order} = DAGServer.topological_sort(s)
    assert length(order) == 50
    assert order == Enum.to_list(1..50)

    edges = for i <- 1..49, do: {i, i + 1}
    assert valid_topological_order?(order, edges)
  end

  test "concurrent conflicting edges never form a cycle", %{server: s} do
    for v <- [:a, :b], do: :ok = DAGServer.add_vertex(s, v)

    results =
      [
        Task.async(fn -> DAGServer.add_edge(s, :a, :b) end),
        Task.async(fn -> DAGServer.add_edge(s, :b, :a) end)
      ]
      |> Enum.map(&Task.await/1)

    # Exactly one direction can succeed; the other must be rejected as a cycle.
    assert Enum.sort(results) == [:ok, {:error, :cycle}]
    assert {:ok, order} = DAGServer.topological_sort(s)
    assert length(order) == 2
  end

  test "rejected cycle edge is not committed to the graph", %{server: s} do
    for v <- [:a, :b, :c], do: :ok = DAGServer.add_vertex(s, v)
    :ok = DAGServer.add_edge(s, :a, :b)
    :ok = DAGServer.add_edge(s, :b, :c)

    assert {:error, :cycle} = DAGServer.add_edge(s, :c, :a)

    assert DAGServer.successors(s, :c) == []
    assert DAGServer.predecessors(s, :a) == []
    assert {:ok, order} = DAGServer.topological_sort(s)
    assert order == [:a, :b, :c]
    assert valid_topological_order?(order, [{:a, :b}, {:b, :c}])
  end

  test "missing source endpoint is rejected just like a missing target", %{server: s} do
    :ok = DAGServer.add_vertex(s, :a)

    assert {:error, :vertex_not_found} = DAGServer.add_edge(s, :ghost, :a)
    assert {:error, :vertex_not_found} = DAGServer.add_edge(s, :ghost, :phantom)

    assert DAGServer.vertices(s) == [:a]
    assert DAGServer.predecessors(s, :a) == []
  end

  test "start_link forwards opts so the server is reachable by registered name" do
    name = :dag_server_named_opts_test

    assert {:ok, pid} = DAGServer.start_link(name: name)
    assert is_pid(pid)
    assert Process.whereis(name) == pid

    assert :ok = DAGServer.add_vertex(name, :x)
    assert :ok = DAGServer.add_vertex(name, :y)
    assert :ok = DAGServer.add_edge(name, :x, :y)
    assert {:ok, [:x, :y]} = DAGServer.topological_sort(name)
    assert DAGServer.successors(name, :x) == [:y]
  end

  test "vertices may be arbitrary terms such as tuples, maps, strings and lists", %{server: s} do
    terms = [{:job, 1}, %{id: "m"}, "build", [1, 2, 3], 7]
    for v <- terms, do: assert(:ok = DAGServer.add_vertex(s, v))

    assert :ok = DAGServer.add_edge(s, {:job, 1}, %{id: "m"})
    assert :ok = DAGServer.add_edge(s, %{id: "m"}, "build")
    assert {:error, :cycle} = DAGServer.add_edge(s, "build", {:job, 1})

    assert Enum.sort(DAGServer.vertices(s)) == Enum.sort(terms)
    assert DAGServer.successors(s, {:job, 1}) == [%{id: "m"}]
    assert DAGServer.predecessors(s, "build") == [%{id: "m"}]

    assert {:ok, order} = DAGServer.topological_sort(s)
    assert length(order) == 5
    assert valid_topological_order?(order, [{{:job, 1}, %{id: "m"}}, {%{id: "m"}, "build"}])
  end

  test "sort includes isolated vertices and orders a diamond validly", %{server: s} do
    # TODO
  end

  test "neighbour queries report only direct edges, not transitive reachability", %{server: s} do
    for v <- [:a, :b, :c], do: :ok = DAGServer.add_vertex(s, v)
    :ok = DAGServer.add_edge(s, :a, :b)
    :ok = DAGServer.add_edge(s, :b, :c)

    assert DAGServer.predecessors(s, :c) == [:b]
    assert DAGServer.successors(s, :a) == [:b]
    assert DAGServer.predecessors(s, :b) == [:a]
    assert DAGServer.successors(s, :b) == [:c]
  end
end
```

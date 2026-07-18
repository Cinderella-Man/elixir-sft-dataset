# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule DAGServer do
  use GenServer

  defstruct vertices: MapSet.new(), out_edges: %{}, in_edges: %{}

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def add_vertex(server, vertex), do: GenServer.call(server, {:add_vertex, vertex})

  def add_edge(server, from, to), do: GenServer.call(server, {:add_edge, from, to})

  def topological_sort(server), do: GenServer.call(server, :topological_sort)

  def predecessors(server, vertex), do: GenServer.call(server, {:predecessors, vertex})

  def successors(server, vertex), do: GenServer.call(server, {:successors, vertex})

  def vertices(server), do: GenServer.call(server, :vertices)

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok), do: {:ok, %__MODULE__{}}

  @impl true
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

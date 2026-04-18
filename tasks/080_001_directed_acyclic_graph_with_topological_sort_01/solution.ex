defmodule DAG do
  @moduledoc """
  A Directed Acyclic Graph (DAG) implemented as a pure data structure.

  Internally the struct holds:
    - `vertices`  – a `MapSet` of all vertices (any term).
    - `out_edges` – a `Map` of `vertex => MapSet of successors`   (forward adjacency).
    - `in_edges`  – a `Map` of `vertex => MapSet of predecessors` (reverse adjacency).

  ## Invariants
    * Every key / value that appears in `out_edges` or `in_edges` is also in `vertices`.
    * The graph is acyclic at all times; `add_edge/3` rejects edges that would form a cycle.
  """

  @enforce_keys [:vertices, :out_edges, :in_edges]
  defstruct [:vertices, :out_edges, :in_edges]

  @type vertex :: term()
  @type t :: %__MODULE__{
          vertices: MapSet.t(),
          out_edges: %{vertex() => MapSet.t()},
          in_edges: %{vertex() => MapSet.t()}
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns an empty DAG."
  @spec new() :: t()
  def new do
    %__MODULE__{
      vertices: MapSet.new(),
      out_edges: %{},
      in_edges: %{}
    }
  end

  @doc """
  Adds `vertex` to the DAG.
  If the vertex already exists the DAG is returned unchanged.
  Vertices may be any Elixir term.
  """
  @spec add_vertex(t(), vertex()) :: t()
  def add_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      dag
    else
      %{
        dag
        | vertices: MapSet.put(dag.vertices, vertex),
          out_edges: Map.put_new(dag.out_edges, vertex, MapSet.new()),
          in_edges: Map.put_new(dag.in_edges, vertex, MapSet.new())
      }
    end
  end

  @doc """
  Adds a directed edge from `from` to `to`.

  Both vertices must already exist in the DAG.

  Returns `{:ok, new_dag}` on success, or `{:error, :cycle}` if the edge
  would introduce a cycle.  Cycle detection is performed eagerly via DFS
  before the edge is committed.
  """
  @spec add_edge(t(), vertex(), vertex()) :: {:ok, t()} | {:error, :cycle}
  def add_edge(%__MODULE__{} = dag, from, to) do
    with :ok <- require_vertex(dag, from),
         :ok <- require_vertex(dag, to),
         :ok <- check_no_cycle(dag, from, to) do
      new_dag = %{
        dag
        | out_edges: Map.update!(dag.out_edges, from, &MapSet.put(&1, to)),
          in_edges: Map.update!(dag.in_edges, to, &MapSet.put(&1, from))
      }

      {:ok, new_dag}
    end
  end

  @doc """
  Returns all vertices that have a direct edge *pointing to* `vertex`
  (i.e. the direct predecessors / dependencies of `vertex`).
  """
  @spec predecessors(t(), vertex()) :: [vertex()]
  def predecessors(%__MODULE__{} = dag, vertex) do
    dag.in_edges
    |> Map.get(vertex, MapSet.new())
    |> MapSet.to_list()
  end

  @doc """
  Returns all vertices that `vertex` has a direct edge *pointing to*
  (i.e. what directly depends on `vertex`).
  """
  @spec successors(t(), vertex()) :: [vertex()]
  def successors(%__MODULE__{} = dag, vertex) do
    dag.out_edges
    |> Map.get(vertex, MapSet.new())
    |> MapSet.to_list()
  end

  @doc """
  Returns `{:ok, ordering}` where `ordering` is a list of every vertex in a
  valid topological order — each vertex appears before all of its successors.

  Uses **Kahn's algorithm** (BFS over in-degrees).

  Returns `{:ok, []}` for an empty graph.  Because `add_edge/3` guarantees the
  graph is always acyclic, this function will always succeed.
  """
  @spec topological_sort(t()) :: {:ok, [vertex()]}
  def topological_sort(%__MODULE__{} = dag) do
    # Build in-degree map: vertex => number of incoming edges
    in_degree =
      Map.new(dag.vertices, fn v ->
        {v, MapSet.size(Map.fetch!(dag.in_edges, v))}
      end)

    # Seed the queue with all vertices that have no incoming edges.
    # Sort for determinism when multiple zero-in-degree vertices exist.
    initial_queue =
      in_degree
      |> Enum.filter(fn {_v, deg} -> deg == 0 end)
      |> Enum.map(fn {v, _} -> v end)
      |> Enum.sort()

    {order, _in_degree} = kahn(initial_queue, in_degree, dag.out_edges, [])

    {:ok, order}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Kahn's BFS loop.
  # `queue`     – list of vertices with in-degree 0 (process head first)
  # `in_degree` – current in-degree map (mutable across iterations)
  # `out_edges` – adjacency (unchanged)
  # `acc`       – reversed result list
  defp kahn([], in_degree, _out_edges, acc), do: {Enum.reverse(acc), in_degree}

  defp kahn([v | rest], in_degree, out_edges, acc) do
    # Decrement in-degree for every successor of v
    {new_in_degree, newly_zero} =
      out_edges
      |> Map.fetch!(v)
      |> Enum.reduce({in_degree, []}, fn succ, {deg_map, zeros} ->
        new_deg = Map.fetch!(deg_map, succ) - 1
        updated = Map.put(deg_map, succ, new_deg)

        if new_deg == 0 do
          {updated, [succ | zeros]}
        else
          {updated, zeros}
        end
      end)

    # Append newly-zero vertices in sorted order for determinism
    new_queue = rest ++ Enum.sort(newly_zero)

    kahn(new_queue, new_in_degree, out_edges, [v | acc])
  end

  # Returns :ok if `vertex` is in the DAG, otherwise {:error, :vertex_not_found}.
  defp require_vertex(dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      :ok
    else
      {:error, :vertex_not_found}
    end
  end

  @doc false
  # Eagerly checks whether adding the edge from→to would create a cycle.
  #
  # A cycle exists iff `from` is already reachable *from* `to` via the current
  # out-edges (because after insertion there would be a path to→...→from→to).
  # We also handle the self-loop case (from == to) explicitly.
  #
  # Uses iterative DFS with an explicit stack to avoid blowing the call stack
  # on deep graphs.
  defp check_no_cycle(_dag, from, from), do: {:error, :cycle}

  defp check_no_cycle(dag, from, to) do
    # DFS from `to` following out_edges; if we ever reach `from`, it's a cycle.
    if dfs_reaches?(dag.out_edges, to, from) do
      {:error, :cycle}
    else
      :ok
    end
  end

  # Iterative DFS: returns true if `target` is reachable from `start`.
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
        neighbors =
          out_edges
          |> Map.get(node, MapSet.new())
          |> MapSet.to_list()

        do_dfs(neighbors ++ stack, MapSet.put(visited, node), out_edges, target)
    end
  end
end

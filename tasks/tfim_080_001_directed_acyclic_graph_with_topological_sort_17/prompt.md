# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
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
```

## Test harness — implement the `# TODO` test

```elixir
defmodule DAGTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Checks that every vertex in `edges` appears before its dependent
  # in the given ordering list.
  defp valid_topological_order?(ordering, edges) do
    index = ordering |> Enum.with_index() |> Map.new()

    Enum.all?(edges, fn {from, to} ->
      Map.fetch!(index, from) < Map.fetch!(index, to)
    end)
  end

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/0 returns an empty DAG" do
    dag = DAG.new()
    assert {:ok, []} = DAG.topological_sort(dag)
  end

  test "add_vertex/2 adds vertices; duplicates are ignored" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:a)

    {:ok, order} = DAG.topological_sort(dag)
    assert Enum.sort(order) == [:a, :b]
  end

  test "add_edge/3 returns {:ok, dag} on success" do
    dag = DAG.new() |> DAG.add_vertex(:a) |> DAG.add_vertex(:b)
    assert {:ok, _dag} = DAG.add_edge(dag, :a, :b)
  end

  # -------------------------------------------------------
  # Cycle detection
  # -------------------------------------------------------

  test "direct cycle (a -> b -> a) is rejected" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    assert {:error, :cycle} = DAG.add_edge(dag, :b, :a)
  end

  test "self-loop (a -> a) is rejected" do
    dag = DAG.new() |> DAG.add_vertex(:a)
    assert {:error, :cycle} = DAG.add_edge(dag, :a, :a)
  end

  test "indirect cycle (a -> b -> c -> a) is rejected" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :b, :c)
    assert {:error, :cycle} = DAG.add_edge(dag, :c, :a)
  end

  test "non-cycle-forming edges are all accepted" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)
      |> DAG.add_vertex(:d)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :a, :c)
    {:ok, dag} = DAG.add_edge(dag, :b, :d)
    {:ok, _dag} = DAG.add_edge(dag, :c, :d)
  end

  # -------------------------------------------------------
  # Topological sort
  # -------------------------------------------------------

  test "topological sort of a linear chain" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :b, :c)

    assert {:ok, order} = DAG.topological_sort(dag)
    assert order == [:a, :b, :c]
  end

  test "topological sort is valid for a diamond graph" do
    #     a
    #    / \
    #   b   c
    #    \ /
    #     d
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)
      |> DAG.add_vertex(:d)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :a, :c)
    {:ok, dag} = DAG.add_edge(dag, :b, :d)
    {:ok, dag} = DAG.add_edge(dag, :c, :d)

    assert {:ok, order} = DAG.topological_sort(dag)

    edges = [{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}]
    assert valid_topological_order?(order, edges)
    assert length(order) == 4
  end

  test "topological sort includes isolated vertices" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:isolated)
      |> DAG.add_vertex(:b)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)

    assert {:ok, order} = DAG.topological_sort(dag)
    assert :isolated in order
    assert length(order) == 3
  end

  test "topological sort is valid for a known dependency graph" do
    # Simulates: mix -> hex -> ssl -> crypto
    #                        -> public_key -> crypto
    vertices = [:mix, :hex, :ssl, :crypto, :public_key]

    edges = [
      {:mix, :hex},
      {:hex, :ssl},
      {:ssl, :crypto},
      {:ssl, :public_key},
      {:public_key, :crypto}
    ]

    dag = Enum.reduce(vertices, DAG.new(), &DAG.add_vertex(&2, &1))

    dag =
      Enum.reduce(edges, dag, fn {from, to}, acc ->
        {:ok, updated} = DAG.add_edge(acc, from, to)
        updated
      end)

    assert {:ok, order} = DAG.topological_sort(dag)
    assert valid_topological_order?(order, edges)
    assert length(order) == length(vertices)
  end

  # -------------------------------------------------------
  # Predecessors & successors
  # -------------------------------------------------------

  test "successors/2 returns direct outgoing neighbours" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)
    {:ok, dag} = DAG.add_edge(dag, :a, :c)

    assert Enum.sort(DAG.successors(dag, :a)) == [:b, :c]
    assert DAG.successors(dag, :b) == []
  end

  test "predecessors/2 returns direct incoming neighbours" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)
      |> DAG.add_vertex(:c)

    {:ok, dag} = DAG.add_edge(dag, :a, :c)
    {:ok, dag} = DAG.add_edge(dag, :b, :c)

    assert Enum.sort(DAG.predecessors(dag, :c)) == [:a, :b]
    assert DAG.predecessors(dag, :a) == []
  end

  test "predecessors and successors are consistent with each other" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:x)
      |> DAG.add_vertex(:y)
      |> DAG.add_vertex(:z)

    {:ok, dag} = DAG.add_edge(dag, :x, :y)
    {:ok, dag} = DAG.add_edge(dag, :x, :z)

    assert :x in DAG.predecessors(dag, :y)
    assert :x in DAG.predecessors(dag, :z)
    assert :y in DAG.successors(dag, :x)
    assert :z in DAG.successors(dag, :x)
  end

  test "vertices may be arbitrary terms and still sort and link correctly" do
    a = {:job, "compile", 1}
    b = %{name: "link", tags: [1, 2]}
    c = "release"

    dag =
      DAG.new()
      |> DAG.add_vertex(a)
      |> DAG.add_vertex(b)
      |> DAG.add_vertex(c)

    {:ok, dag} = DAG.add_edge(dag, a, b)
    {:ok, dag} = DAG.add_edge(dag, b, c)

    assert {:ok, order} = DAG.topological_sort(dag)
    assert order == [a, b, c]
    assert DAG.successors(dag, a) == [b]
    assert DAG.predecessors(dag, c) == [b]
  end

  test "an edge rejected as a cycle leaves the graph completely unmodified" do
    # TODO
  end

  test "add_edge/3 does not succeed when either endpoint is missing" do
    dag = DAG.new() |> DAG.add_vertex(:a)

    refute match?({:ok, _}, DAG.add_edge(dag, :a, :ghost))
    refute match?({:ok, _}, DAG.add_edge(dag, :ghost, :a))

    assert {:ok, [:a]} = DAG.topological_sort(dag)
    assert DAG.successors(dag, :a) == []
    assert DAG.predecessors(dag, :a) == []
  end

  test "re-adding an existing vertex preserves its existing edges" do
    dag =
      DAG.new()
      |> DAG.add_vertex(:a)
      |> DAG.add_vertex(:b)

    {:ok, dag} = DAG.add_edge(dag, :a, :b)

    re_added = dag |> DAG.add_vertex(:a) |> DAG.add_vertex(:b)

    assert re_added == dag
    assert DAG.successors(re_added, :a) == [:b]
    assert DAG.predecessors(re_added, :b) == [:a]
    assert {:ok, [:a, :b]} = DAG.topological_sort(re_added)
  end

  test "structurally equal compound vertices count as one vertex" do
    key = {:pkg, "hex", %{opt: [:only, :dev]}}
    same = {:pkg, "hex", %{opt: [:only, :dev]}}

    dag =
      DAG.new()
      |> DAG.add_vertex(key)
      |> DAG.add_vertex(same)
      |> DAG.add_vertex(:tail)

    {:ok, dag} = DAG.add_edge(dag, same, :tail)

    assert {:ok, order} = DAG.topological_sort(dag)
    assert length(order) == 2
    assert DAG.successors(dag, key) == [:tail]
    assert DAG.predecessors(dag, :tail) == [key]
  end
end
```

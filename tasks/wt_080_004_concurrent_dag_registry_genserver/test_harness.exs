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
end

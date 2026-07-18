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
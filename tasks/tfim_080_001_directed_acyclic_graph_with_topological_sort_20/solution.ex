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
  test "missing vertex is rejected" do
    dag = MutableDAG.new() |> MutableDAG.add_vertex(:a)
    assert {:error, :vertex_not_found} = MutableDAG.add_edge(dag, :a, :ghost)
  end
  test "empty graph" do
    dag = MutableDAG.new()
    assert {:ok, []} = MutableDAG.topological_sort(dag)
    assert {:ok, []} = MutableDAG.topological_layers(dag)
  end
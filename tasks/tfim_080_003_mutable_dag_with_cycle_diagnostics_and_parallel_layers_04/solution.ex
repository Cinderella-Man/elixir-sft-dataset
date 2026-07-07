  test "self-loop reports [a, a]" do
    dag = MutableDAG.new() |> MutableDAG.add_vertex(:a)
    assert {:error, {:cycle, [:a, :a]}} = MutableDAG.add_edge(dag, :a, :a)
  end
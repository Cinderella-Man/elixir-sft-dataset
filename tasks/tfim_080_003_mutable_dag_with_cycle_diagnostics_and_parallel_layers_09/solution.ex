  test "isolated vertices sit in layer 0" do
    dag = build([:a, :b, :iso], [{:a, :b}])
    assert {:ok, [[:a, :iso], [:b]]} = MutableDAG.topological_layers(dag)
  end
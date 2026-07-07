  test "direct back edge reports two-hop cycle" do
    dag = build([:a, :b], [{:a, :b}])
    assert {:error, {:cycle, [:b, :a, :b]}} = MutableDAG.add_edge(dag, :b, :a)
  end
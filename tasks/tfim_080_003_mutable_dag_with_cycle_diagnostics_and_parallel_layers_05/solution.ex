  test "cycle-forming edge reports the offending path from->...->from" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])
    assert {:error, {:cycle, [:c, :a, :b, :c]}} = MutableDAG.add_edge(dag, :c, :a)
  end
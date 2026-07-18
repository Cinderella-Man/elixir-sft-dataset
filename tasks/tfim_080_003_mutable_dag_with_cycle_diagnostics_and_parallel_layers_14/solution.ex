  test "re-adding a vertex does not reopen a cycle-forming edge" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])
    dag = MutableDAG.add_vertex(dag, :b)

    assert {:error, {:cycle, [:c, :a, :b, :c]}} = MutableDAG.add_edge(dag, :c, :a)
  end
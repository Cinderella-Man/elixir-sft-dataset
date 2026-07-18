  test "remove_edge lets a previously-cyclic edge succeed" do
    dag = build([:a, :b, :c], [{:a, :b}, {:b, :c}])
    assert {:error, {:cycle, _}} = MutableDAG.add_edge(dag, :c, :a)

    dag = MutableDAG.remove_edge(dag, :b, :c)
    assert {:ok, _dag} = MutableDAG.add_edge(dag, :c, :a)
  end
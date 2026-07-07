  test "direct cycle is rejected eagerly" do
    dag = build([{:a, 1}, {:b, 1}], [{:a, :b}])
    assert {:error, :cycle} = WeightedDAG.add_dependency(dag, :b, :a)
  end
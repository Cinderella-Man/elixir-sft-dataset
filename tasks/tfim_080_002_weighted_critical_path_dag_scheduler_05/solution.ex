  test "indirect cycle is rejected" do
    dag = build([{:a, 1}, {:b, 1}, {:c, 1}], [{:a, :b}, {:b, :c}])
    assert {:error, :cycle} = WeightedDAG.add_dependency(dag, :c, :a)
  end
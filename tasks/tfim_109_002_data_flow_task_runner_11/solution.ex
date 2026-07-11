  test "a self-dependency is a cycle" do
    DataFlowRunner.submit(:runner, :a, depends_on: [:a], func: fn _ -> 1 end)
    assert {:error, {:cycle, _}} = DataFlowRunner.run_all(:runner)
  end
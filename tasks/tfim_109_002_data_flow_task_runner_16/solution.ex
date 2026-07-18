  test "cycle report lists only the tasks participating in the cycle" do
    DataFlowRunner.submit(:runner, :a, depends_on: [:b], func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: fn _ -> 2 end)
    DataFlowRunner.submit(:runner, :downstream, depends_on: [:a], func: fn _ -> 3 end)

    assert {:error, {:cycle, involved}} = DataFlowRunner.run_all(:runner)
    assert Enum.sort(involved) == [:a, :b]
  end
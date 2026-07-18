  test "input map excludes results of tasks that were not declared as dependencies" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, func: fn _ -> 2 end)
    DataFlowRunner.submit(:runner, :c, depends_on: [:a], func: fn inputs -> inputs end)

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results.c == %{a: 1}
  end
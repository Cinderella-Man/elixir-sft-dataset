  test "a dependent task receives its dependency's result" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 10 end)
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: fn %{a: v} -> v + 5 end)

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{a: 10, b: 15}
  end
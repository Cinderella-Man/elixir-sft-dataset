  test "resubmitting replaces the previous dependency list, not just the func" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, depends_on: [:a, :ghost], func: fn _ -> :old end)
    DataFlowRunner.submit(:runner, :b, func: fn inputs -> {:new, inputs} end)

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{a: 1, b: {:new, %{}}}
  end
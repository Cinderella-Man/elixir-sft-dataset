  test "a task with multiple deps receives all of their results" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, func: fn _ -> 2 end)

    DataFlowRunner.submit(:runner, :c,
      depends_on: [:a, :b],
      func: fn inputs -> inputs end
    )

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results.c == %{a: 1, b: 2}
  end
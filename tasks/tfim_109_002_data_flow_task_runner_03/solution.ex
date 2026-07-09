  test "a task with no dependencies receives an empty input map" do
    assert :ok =
             DataFlowRunner.submit(:runner, :a, func: fn inputs -> {:got, map_size(inputs)} end)

    assert {:ok, %{a: {:got, 0}}} = DataFlowRunner.run_all(:runner)
  end
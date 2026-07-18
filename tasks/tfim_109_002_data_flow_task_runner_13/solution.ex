  test "resubmitting a task overwrites its definition" do
    DataFlowRunner.submit(:runner, :a, func: fn _ -> :first end)
    DataFlowRunner.submit(:runner, :a, func: fn _ -> :second end)

    assert {:ok, %{a: :second}} = DataFlowRunner.run_all(:runner)
  end
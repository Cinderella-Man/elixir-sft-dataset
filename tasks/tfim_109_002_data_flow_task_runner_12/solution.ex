  test "reports unknown dependencies and runs nothing" do
    DataFlowRunner.submit(:runner, :real, func: rec(:real, 0, fn _ -> :ok end))
    DataFlowRunner.submit(:runner, :b, depends_on: [:ghost], func: rec(:b, 0, fn _ -> :ok end))

    assert {:error, {:unknown_dependencies, missing}} = DataFlowRunner.run_all(:runner)
    assert :ghost in missing
    assert Recorder.events() == []
  end
  test "a cycle prevents an otherwise runnable independent task from executing" do
    DataFlowRunner.submit(:runner, :x, depends_on: [:y], func: rec(:x, 0, fn _ -> 1 end))
    DataFlowRunner.submit(:runner, :y, depends_on: [:x], func: rec(:y, 0, fn _ -> 2 end))
    DataFlowRunner.submit(:runner, :free, func: rec(:free, 0, fn _ -> :ran end))

    assert {:error, {:cycle, _}} = DataFlowRunner.run_all(:runner)
    assert Recorder.events() == []
    assert Recorder.started_at(:free) == nil
  end
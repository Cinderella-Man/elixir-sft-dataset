  test "independent sibling tasks overlap in time" do
    DataFlowRunner.submit(:runner, :a, func: rec(:a, 40, fn _ -> 0 end))
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: rec(:b, 150, fn _ -> :b end))
    DataFlowRunner.submit(:runner, :c, depends_on: [:a], func: rec(:c, 150, fn _ -> :c end))

    assert {:ok, _} = DataFlowRunner.run_all(:runner)
    assert Recorder.started_at(:b) < Recorder.ended_at(:c)
    assert Recorder.started_at(:c) < Recorder.ended_at(:b)
  end
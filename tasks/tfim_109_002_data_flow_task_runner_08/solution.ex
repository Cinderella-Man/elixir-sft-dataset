  test "a dependent task starts only after its dependency finished" do
    DataFlowRunner.submit(:runner, :a, func: rec(:a, 50, fn _ -> 1 end))
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: rec(:b, 10, fn %{a: v} -> v end))

    assert {:ok, _} = DataFlowRunner.run_all(:runner)
    assert Recorder.ended_at(:a) <= Recorder.started_at(:b)
  end
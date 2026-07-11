  test "a dependent task starts only after its dependency has finished" do
    TaskRunner.submit(:runner, :a, func: task(:a, 50))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 10))

    assert {:ok, _} = TaskRunner.run_all(:runner)

    assert Recorder.ended_at(:a) <= Recorder.started_at(:b)
  end
  test "independent sibling tasks overlap in time" do
    TaskRunner.submit(:runner, :a, func: task(:a, 40))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 150))
    TaskRunner.submit(:runner, :c, depends_on: [:a], func: task(:c, 150))

    assert {:ok, _} = TaskRunner.run_all(:runner)

    # Overlap test: each starts before the other ends.
    assert Recorder.started_at(:b) < Recorder.ended_at(:c)
    assert Recorder.started_at(:c) < Recorder.ended_at(:b)
  end
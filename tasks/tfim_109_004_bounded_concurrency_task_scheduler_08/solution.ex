  test "dependency ordering is respected under a concurrency cap" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, func: task(:a, 40))
    BoundedRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 10))

    assert {:ok, _} = BoundedRunner.run_all(:runner)
    assert Tracker.ended_at(:a) <= Tracker.started_at(:b)
  end
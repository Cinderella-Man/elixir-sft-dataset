  test "diamond DAG produces correct results with a cap" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, func: task(:a, 0, 1))
    BoundedRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 0, 2))
    BoundedRunner.submit(:runner, :c, depends_on: [:a], func: task(:c, 0, 3))
    BoundedRunner.submit(:runner, :d, depends_on: [:b, :c], func: task(:d, 0, 4))

    assert {:ok, %{a: 1, b: 2, c: 3, d: 4}} = BoundedRunner.run_all(:runner)
    assert Tracker.ended_at(:b) <= Tracker.started_at(:d)
    assert Tracker.ended_at(:c) <= Tracker.started_at(:d)
  end
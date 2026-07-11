  test "a high budget lets independent tasks overlap" do
    start_runner(8)
    BoundedRunner.submit(:runner, :a, func: task(:a, 100))
    BoundedRunner.submit(:runner, :b, func: task(:b, 100))
    BoundedRunner.submit(:runner, :c, func: task(:c, 100))

    assert {:ok, _} = BoundedRunner.run_all(:runner)
    assert Tracker.max_seen() == 3
  end
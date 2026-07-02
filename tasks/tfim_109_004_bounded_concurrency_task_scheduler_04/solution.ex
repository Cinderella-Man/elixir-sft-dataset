  test "concurrency never exceeds max even with many ready tasks" do
    start_runner(2)

    for i <- 1..6 do
      id = :"job_#{i}"
      BoundedRunner.submit(:runner, id, func: task(id, 60))
    end

    assert {:ok, results} = BoundedRunner.run_all(:runner)
    assert map_size(results) == 6
    assert Tracker.max_seen() <= 2
  end
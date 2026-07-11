  test "with max_concurrency 1 execution is fully serial" do
    start_runner(1)

    for i <- 1..4 do
      id = :"job_#{i}"
      BoundedRunner.submit(:runner, id, func: task(id, 20))
    end

    assert {:ok, results} = BoundedRunner.run_all(:runner)
    assert map_size(results) == 4
    assert Tracker.max_seen() == 1
  end
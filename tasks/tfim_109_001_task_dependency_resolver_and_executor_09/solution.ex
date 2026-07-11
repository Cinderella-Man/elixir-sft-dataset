  test "a wide layer of independent tasks runs concurrently (wall-clock)" do
    for i <- 1..5 do
      id = :"job_#{i}"
      TaskRunner.submit(:runner, id, func: task(id, 120))
    end

    {elapsed_us, {:ok, results}} =
      :timer.tc(fn -> TaskRunner.run_all(:runner) end)

    elapsed_ms = div(elapsed_us, 1000)

    assert map_size(results) == 5
    # Sequential would be ~600ms; parallel should be far less.
    assert elapsed_ms < 400
    # Sanity: the tasks actually ran (didn't skip the sleep).
    assert elapsed_ms >= 100
  end
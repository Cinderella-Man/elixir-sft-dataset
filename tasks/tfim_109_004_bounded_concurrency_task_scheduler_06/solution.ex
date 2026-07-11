  test "bounded runner takes multiple waves (wall clock)" do
    start_runner(2)

    for i <- 1..6 do
      id = :"job_#{i}"
      BoundedRunner.submit(:runner, id, func: task(id, 80))
    end

    {elapsed_us, {:ok, _}} = :timer.tc(fn -> BoundedRunner.run_all(:runner) end)
    elapsed_ms = div(elapsed_us, 1000)

    # 6 tasks, 2 at a time, 80ms each => ~3 waves => >= ~240ms.
    assert elapsed_ms >= 200
  end
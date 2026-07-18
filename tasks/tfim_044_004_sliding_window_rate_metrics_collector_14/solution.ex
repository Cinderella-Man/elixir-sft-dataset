  test "increment succeeds while the owning process cannot serve requests", %{clock: clock} do
    set_time(clock, 3)
    owner = Process.whereis(Metrics)
    :sys.suspend(owner)

    task = Task.async(fn -> Metrics.increment(:direct, 4) end)
    outcome = Task.yield(task, 2_000)
    :sys.resume(owner)

    assert {:ok, :ok} = outcome
    assert Metrics.count(:direct) == 4
  end
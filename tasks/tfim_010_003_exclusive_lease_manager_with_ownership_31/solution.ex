  test "sweep runs automatically on a finite interval and keeps re-arming", %{mgr: _mgr} do
    {:ok, sweeper} =
      LeaseManager.start_link(
        clock: &Clock.now/0,
        lease_duration_ms: 1_000,
        cleanup_interval_ms: 25
      )

    on_exit(fn ->
      try do
        GenServer.stop(sweeper)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, _} = LeaseManager.acquire(sweeper, :printer, :alice)

    # Leave the clock past expiry so an automatic pass sees an expired lease.
    Clock.set(10_000)
    assert await_swept(sweeper, :printer, 500, 10_000, 1_000)

    # A second lease, expired later, is swept as well: the timer is periodic
    # rather than a single one-shot pass.
    Clock.set(20_000)
    {:ok, _} = LeaseManager.acquire(sweeper, :printer, :bob)

    Clock.set(30_000)
    assert await_swept(sweeper, :printer, 20_500, 30_000, 1_000)
  end
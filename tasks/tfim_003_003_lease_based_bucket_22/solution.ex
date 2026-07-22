  test "start_link registers under :name and serves calls through it" do
    name = :"lease_bucket_#{System.pid()}_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      LeaseBucket.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        name: name
      )

    assert Process.whereis(name) == pid
    assert {:ok, _lease, 2} = LeaseBucket.acquire_lease(name, "named", 3, 1.0, 1, 60_000)
    assert {:ok, 1} = LeaseBucket.active_leases(name, "named")
  end
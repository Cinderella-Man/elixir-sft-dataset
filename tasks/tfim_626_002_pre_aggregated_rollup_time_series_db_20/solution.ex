  test "cleanup_interval_ms of :infinity arms no automatic cleanup at all" do
    test_pid = self()

    clock = fn ->
      send(test_pid, :clock_read)
      0
    end

    {:ok, _db} = RollupTSDB.start_link(clock: clock, cleanup_interval_ms: :infinity)

    refute_receive :clock_read, 300
  end
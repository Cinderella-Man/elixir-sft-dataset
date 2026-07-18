  test "automatic cleanup re-arms itself after each run" do
    test_pid = self()

    clock = fn ->
      send(test_pid, :clock_read)
      0
    end

    {:ok, _db} = RollupTSDB.start_link(clock: clock, cleanup_interval_ms: 10)

    assert_receive :clock_read, 1_000
    assert_receive :clock_read, 1_000
  end
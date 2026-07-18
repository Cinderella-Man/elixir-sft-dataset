  test "cleanup runs on its own repeatedly on the cleanup interval" do
    test_pid = self()

    # The injected clock is only consulted by cleanup, so each read announces
    # that a cleanup pass ran without the test ever sending :cleanup itself.
    clock = fn ->
      send(test_pid, :cleanup_ran)
      1_000_000
    end

    {:ok, db} =
      CounterTSDB.start_link(
        clock: clock,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: 25
      )

    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 1)

    # Two unsolicited passes: cleanup is scheduled again after it runs.
    assert_receive :cleanup_ran, 2_000
    assert_receive :cleanup_ran, 2_000

    # The chunk holding the point expired long before the clock's 1_000_000,
    # so the automatic pass dropped both the chunk and its now-empty series.
    assert [] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 2_000_000})
  end
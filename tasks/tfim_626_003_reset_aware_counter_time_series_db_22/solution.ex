  test "the name option registers the process for public API calls" do
    {:ok, _pid} =
      CounterTSDB.start_link(
        name: :counter_tsdb_named_test,
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    :ok = CounterTSDB.insert(:counter_tsdb_named_test, "reqs", %{"i" => "a"}, 100, 5)
    :ok = CounterTSDB.insert(:counter_tsdb_named_test, "reqs", %{"i" => "a"}, 200, 9)

    assert [{%{"i" => "a"}, [{100, 5}, {200, 9}]}] =
             CounterTSDB.query(:counter_tsdb_named_test, "reqs", %{"i" => "a"}, {0, 500})
  end
  test "rate is per-second reset-aware increase", %{db: db} do
    # increase = 60; elapsed = (500-0)/1000 = 0.5s; rate = 120.0
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 100)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 500, 160)

    [{_labels, [{0, rate}]}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :rate, 1_000)
    assert_in_delta rate, 120.0, 0.01
  end
  test "query_agg :rate computes per-second rate of change", %{db: db} do
    # Window [0, 1000): value goes from 100 at t=0 to 200 at t=500
    # rate = (200 - 100) / ((500 - 0) / 1000) = 100 / 0.5 = 200.0
    :ok = TSDB.insert(db, "m", %{}, 0, 100)
    :ok = TSDB.insert(db, "m", %{}, 500, 200)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 1000}, :rate, 1_000)

    [{0, rate}] = agg_points
    assert_in_delta rate, 200.0, 0.01
  end
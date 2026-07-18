  test "query_agg :rate omits windows with fewer than 2 points", %{db: db} do
    # Window [0, 1000): only 1 point — should be omitted
    :ok = TSDB.insert(db, "m", %{}, 100, 42)
    # Window [1000, 2000): 2 points — should be included
    :ok = TSDB.insert(db, "m", %{}, 1100, 10)
    :ok = TSDB.insert(db, "m", %{}, 1600, 60)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :rate, 1_000)

    # Only the second window
    assert length(agg_points) == 1
    [{1000, rate}] = agg_points
    # (60 - 10) / ((1600 - 1100) / 1000) = 50 / 0.5 = 100.0
    assert_in_delta rate, 100.0, 0.01
  end
  test "query_agg :avg computes the mean per window", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 10)
    :ok = TSDB.insert(db, "m", %{}, 200, 20)
    :ok = TSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 1000}, :avg, 1_000)

    [{0, avg_value}] = agg_points
    assert_in_delta avg_value, 20.0, 0.01
  end
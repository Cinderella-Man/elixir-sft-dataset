  test "query_agg :max returns the maximum value per window", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 10)
    :ok = TSDB.insert(db, "m", %{}, 200, 50)
    :ok = TSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 1000}, :max, 1_000)

    assert agg_points == [{0, 50}]
  end
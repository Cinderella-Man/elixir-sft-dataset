  test "query_agg omits windows with no data points", %{db: db} do
    # Points only in window [0, 1000), nothing in [1000, 2000)
    :ok = TSDB.insert(db, "m", %{}, 100, 1)
    :ok = TSDB.insert(db, "m", %{}, 200, 2)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 1_000)

    assert agg_points == [{0, 3}]
  end
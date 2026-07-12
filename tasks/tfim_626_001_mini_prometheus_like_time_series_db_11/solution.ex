  test "query_agg :sum computes the sum per window", %{db: db} do
    # Insert points: step_ms = 1000
    # Window [0, 1000): timestamps 100, 200, 300
    :ok = TSDB.insert(db, "m", %{}, 100, 10)
    :ok = TSDB.insert(db, "m", %{}, 200, 20)
    :ok = TSDB.insert(db, "m", %{}, 300, 30)
    # Window [1000, 2000): timestamps 1100, 1500
    :ok = TSDB.insert(db, "m", %{}, 1100, 5)
    :ok = TSDB.insert(db, "m", %{}, 1500, 15)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 1_000)

    assert agg_points == [{0, 60}, {1000, 20}]
  end
  test "query_agg :avg computes the mean per window", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 200, 20)
    :ok = ShardedTSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, [{0, avg}]}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 1000}, :avg, 1_000)
    assert_in_delta avg, 20.0, 0.01
  end
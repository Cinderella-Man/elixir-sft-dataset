  test "query_agg :max returns the maximum per window", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 200, 50)
    :ok = ShardedTSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 1000}, :max, 1_000)
    assert agg == [{0, 50}]
  end
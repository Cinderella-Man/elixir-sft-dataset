  test "query_agg :max reports the maximum per window across windows", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 600, 50)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1200, 5)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 2000}, :max, 1_000)
    assert agg == [{0, 50}, {1000, 5}]
  end